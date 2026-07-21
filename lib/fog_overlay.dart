import 'dart:math' show Point, sin, cos, sqrt, atan2;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import 'color_extraction.dart';
import 'fog_texture.dart';
import 'fog_tiling.dart';
import 'models/completed_collage.dart';
import 'photo_pin.dart';

const _deg2rad = 3.141592653589793 / 180;

/// 地図全体を霧で覆い、同じ主要色を持つ写真ピンが3点以上ある色グループの
/// 凸包ポリゴン領域だけを透明にするレイヤー。
///
/// 対象となるのは散歩の記録中（記録開始〜終了の間）に撮影されたピン
/// （[PhotoPin.capturedDuringWalk] が true のもの）のみ。
/// [photoPins] の各ピンが持つ [colorIds] を元にグループ化する。
/// [maxDistanceMeters] より離れたピン同士は別クラスタとして扱い、
/// 同一クラスタ内で 3 点以上集まった場合のみ霧が晴れる。
class FogOverlay extends StatelessWidget {
  final List<PhotoPin> photoPins;
  final Color fogColor;

  /// 完成済みコラージュ。完成した領域は、ライブのクラスタ条件に関係なく
  /// 常に地図上に表示し続ける（完成後もポリゴンが消えないようにするため）。
  final List<CompletedCollage> completedCollages;

  /// 同じ色グループとみなすピン間の最大距離（メートル）
  final double maxDistanceMeters;

  /// 色ピンで囲まれた（霧が晴れた）領域がタップされたときに呼ばれる。
  /// 引数はそのクラスタの colorId（24色パレットのインデックス）と、
  /// そのクラスタ（その領域）を構成する写真ピンのリスト。
  final void Function(int colorId, List<PhotoPin> pins)? onRegionTap;

  const FogOverlay({
    super.key,
    required this.photoPins,
    this.completedCollages = const [],
    this.fogColor = const Color(0xFFF4F6F9),
    this.maxDistanceMeters = 1000.0,
    this.onRegionTap,
  });

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final painter = _FogPainter(
      camera: camera,
      photoPins: photoPins,
      completedCollages: completedCollages,
      fogColor: fogColor,
      maxDistanceMeters: maxDistanceMeters,
    );

    final content = CustomPaint(size: Size.infinite, painter: painter);

    final onTap = onRegionTap;
    if (onTap == null) {
      return IgnorePointer(child: content);
    }

    // translucent にすることで、タップ位置がヒットしなくても
    // 地図の他レイヤー（マーカーやパン操作）への伝播を妨げない。
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (details) {
        final hit = painter.clusterAtPoint(details.localPosition);
        if (hit != null) onTap(hit.colorId, hit.pins);
      },
      child: content,
    );
  }
}

class _FogPainter extends CustomPainter {
  final MapCamera camera;
  final List<PhotoPin> photoPins;
  final List<CompletedCollage> completedCollages;
  final Color fogColor;
  final double maxDistanceMeters;

  const _FogPainter({
    required this.camera,
    required this.photoPins,
    required this.completedCollages,
    required this.fogColor,
    required this.maxDistanceMeters,
  });

  // ── Haversine 距離（メートル）────────────────────────
  static double _distanceMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final lat1 = a.latitude * _deg2rad;
    final lat2 = b.latitude * _deg2rad;
    final dLat = (b.latitude - a.latitude) * _deg2rad;
    final dLon = (b.longitude - a.longitude) * _deg2rad;
    final s = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(s), sqrt(1 - s));
  }

  // ── Union-Find ─────────────────────────────────────
  static List<int> _buildParent(int n) => List<int>.generate(n, (i) => i);

  static int _find(List<int> parent, int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  }

  static void _union(List<int> parent, int a, int b) {
    parent[_find(parent, a)] = _find(parent, b);
  }

  /// colorId → ピンリストに分解したあと、距離でさらにサブクラスタ分割する。

  List<({int colorId, List<PhotoPin> pins})> _buildClusters() {
    // 領域（色クラスタ）の対象は、散歩を記録中に撮影されたピンのみ。
    // ギャラリー読み込みなど、記録中以外に追加されたピンは対象外にする。
    final eligiblePins =
        photoPins.where((p) => p.capturedDuringWalk).toList();

    // まず colorId でグループ化
    final Map<int, List<PhotoPin>> byColor = {};
    for (final pin in eligiblePins) {
      for (final id in pin.colorIds) {
        byColor.putIfAbsent(id, () => []).add(pin);
      }
    }

    final result = <({int colorId, List<PhotoPin> pins})>[];

    for (final entry in byColor.entries) {
      final colorId = entry.key;
      final pins = entry.value;
      if (pins.length < 3) continue;

      // Union-Find で距離クラスタリング
      final n = pins.length;
      final parent = _buildParent(n);
      for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++) {
          if (_distanceMeters(pins[i].position, pins[j].position) <=
              maxDistanceMeters) {
            _union(parent, i, j);
          }
        }
      }

      // クラスタごとに集める
      final Map<int, List<PhotoPin>> clusters = {};
      for (int i = 0; i < n; i++) {
        clusters.putIfAbsent(_find(parent, i), () => []).add(pins[i]);
      }

      for (final cluster in clusters.values) {
        if (cluster.length >= 3) {
          result.add((colorId: colorId, pins: cluster));
        }
      }
    }

    return result;
  }

  /// 完成済みコラージュの領域を、ライブのクラスタ条件に関係なく取り出す。
  /// 完成後もその領域（ポリゴン）が地図から消えないようにするため。
  List<({int colorId, List<PhotoPin> pins})> _completedRegions() {
    if (completedCollages.isEmpty) return const [];
    final byId = {for (final p in photoPins) p.id: p};
    final result = <({int colorId, List<PhotoPin> pins})>[];
    for (final cc in completedCollages) {
      final pins = <PhotoPin>[];
      for (final id in cc.pinIds) {
        final p = byId[id];
        if (p != null) pins.add(p);
      }
      if (pins.length >= 3) {
        result.add((colorId: cc.colorId, pins: pins));
      }
    }
    return result;
  }

  /// 雲テクスチャを地図に貼り付けて描く（マップモードの霧と同じ方式）。
  /// 雲 1 枚を実距離 [FogTexture.tileMeters] 四方として扱い、
  /// 地図上の固定点を基準に鏡張りで並べるので、拡大縮小・移動に追従する。
  void _paintFogFill(Canvas canvas, Rect bounds) {
    final placement = FogTiling.compute(
      zoom: camera.zoom,
      center: camera.center,
      size: bounds.size,
      tileMeters: FogTexture.tileMeters,
    );

    FogTexture.paintWorldTiles(
      canvas,
      bounds,
      tileSizePx: placement.tileSizePx,
      offsetX: placement.offsetX,
      offsetY: placement.offsetY,
      fallbackColor: fogColor,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final clusters = _buildClusters();
    final completed = _completedRegions();
    // ライブのクラスタと完成済み領域の両方の霧を晴らす。
    final allRegions = [...clusters, ...completed];

    // ── 霧レイヤー（saveLayer で合成）──
    canvas.saveLayer(bounds, Paint());
    _paintFogFill(canvas, bounds);

    // 晴れている場所は完全に透過させる（にじみ/白いフチを出さない）。
    final clearPaint = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    for (final c in allRegions) {
      final hull = _hullForPins(c.pins);
      if (hull == null) continue;
      canvas.drawPath(hull, clearPaint);
    }

    canvas.restore();

    // ── 色ティントを描画 ──
    for (final c in allRegions) {
      if (c.colorId < 0 || c.colorId >= colorPalette24.length) continue;
      final hull = _hullForPins(c.pins);
      if (hull == null) continue;

      final pc = colorPalette24[c.colorId];
      canvas.drawPath(
        hull,
        Paint()
          ..color = Color.fromRGBO(pc.r, pc.g, pc.b, 0.22)
          ..style = PaintingStyle.fill,
      );
    }

    // ── 完成済み領域は輪郭を描いて「完成した領域」を明示 ──
    for (final c in completed) {
      if (c.colorId < 0 || c.colorId >= colorPalette24.length) continue;
      final hull = _hullForPins(c.pins);
      if (hull == null) continue;

      final pc = colorPalette24[c.colorId];
      canvas.drawPath(
        hull,
        Paint()
          ..color = Color.fromRGBO(pc.r, pc.g, pc.b, 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..isAntiAlias = true,
      );
    }
  }

  /// [point]（ウィジェット座標）が、いずれかの色クラスタの凸包領域内に
  /// あればそのクラスタ（colorId とそれを構成するピン一覧）を返す。
  /// どの領域にも含まれなければ null。
  ({int colorId, List<PhotoPin> pins})? clusterAtPoint(Offset point) {
    // 完成済み領域を優先（タップで完成コラージュを開けるように）。
    for (final c in _completedRegions()) {
      final hull = _hullForPins(c.pins);
      if (hull != null && hull.contains(point)) {
        return c;
      }
    }
    for (final c in _buildClusters()) {
      final hull = _hullForPins(c.pins);
      if (hull != null && hull.contains(point)) {
        return c;
      }
    }
    return null;
  }

  Path? _hullForPins(List<PhotoPin> pins) {
    final pts = pins
        .map((p) => _toOffset(camera.latLngToScreenPoint(p.position)))
        .toList();
    final hull = _convexHull(pts);
    if (hull.length < 3) return null;
    final path = Path();
    path.moveTo(hull[0].dx, hull[0].dy);
    for (int i = 1; i < hull.length; i++) {
      path.lineTo(hull[i].dx, hull[i].dy);
    }
    path.close();
    return path;
  }

  List<Offset> _convexHull(List<Offset> points) {
    if (points.length < 3) return points;
    final sorted = List<Offset>.from(points)
      ..sort((a, b) =>
          a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
    final lower = <Offset>[];
    for (final p in sorted) {
      while (lower.length >= 2 &&
          _cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    final upper = <Offset>[];
    for (final p in sorted.reversed) {
      while (upper.length >= 2 &&
          _cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  double _cross(Offset o, Offset a, Offset b) =>
      (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

  Offset _toOffset(Point<double> point) => Offset(point.x, point.y);

  @override
  bool shouldRepaint(covariant _FogPainter old) =>
      old.camera.center != camera.center ||
      old.camera.zoom != camera.zoom ||
      old.camera.rotation != camera.rotation ||
      old.camera.nonRotatedSize != camera.nonRotatedSize ||
      old.fogColor != fogColor ||
      old.maxDistanceMeters != maxDistanceMeters ||
      !listEquals(old.completedCollages, completedCollages) ||
      !listEquals(old.photoPins, photoPins);
}
