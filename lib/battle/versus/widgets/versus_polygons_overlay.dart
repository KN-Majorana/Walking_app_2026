import 'dart:math' show Point;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../../color_extraction.dart';
import '../../models/polygon.dart';

/// 対戦モード用のポリゴン描画レイヤ（Demotest3-3 の versus_mode_overlay 方式を移植）。
///
/// 特徴:
///   * 各多角形を **独立した Path** として描画（PolygonLayer の
///     ような単純な半透明重ね塗りにしない）。
///   * `holes` を [PathOperation.difference] で切り抜き。
///   * ★ 実行時「視覚的減算」:
///     古いポリゴン P から、それより **新しい** すべてのポリゴン Q を
///     `Path.combine(PathOperation.difference, ...)` で差し引いた結果を
///     描画する。これにより Firestore 側の幾何減算がまだ反映されていない
///     瞬間でも、A∩B の領域は **A（新しい方）の色のみ** で塗られる。
///
/// v6-9 仕様 §7-2 の
///   「A∩B の領域は A の色（半透明）のみで塗る」
/// を実装したもの。
class VersusPolygonsOverlay extends StatelessWidget {
  /// 描画対象の全ポリゴン（自分＋相手、確定・active のみ）。
  final List<WalkPolygon> polygons;

  /// 自分の UID（自分の領域を強調するため）。
  final String? myUid;

  const VersusPolygonsOverlay({
    super.key,
    required this.polygons,
    required this.myUid,
  });

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _VersusPolygonsPainter(
          camera: camera,
          polygons: polygons,
          myUid: myUid,
        ),
      ),
    );
  }
}

class _VersusPolygonsPainter extends CustomPainter {
  final MapCamera camera;
  final List<WalkPolygon> polygons;
  final String? myUid;

  const _VersusPolygonsPainter({
    required this.camera,
    required this.polygons,
    required this.myUid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 描画対象を「確定 & active & 頂点 3 個以上」に絞り、claimStamp 昇順にソート。
    // （頂点追加で claim を更新した多角形が最前面に来る＝最後に主張した側が勝つ）
    final sorted = polygons
        .where((p) => p.confirmed && p.isActive && p.vertices.length >= 3)
        .toList()
      ..sort((a, b) {
        final aT = a.claimStamp?.millisecondsSinceEpoch ?? 0;
        final bT = b.claimStamp?.millisecondsSinceEpoch ?? 0;
        return aT.compareTo(bT);
      });

    // 事前に各ポリゴンの screen-space 外周パスを作っておく（重複計算を避ける）。
    final rawPaths = <ui.Path>[];
    for (final p in sorted) {
      rawPaths.add(_ringToPath(p.vertices));
    }

    for (int i = 0; i < sorted.length; i++) {
      final p = sorted[i];

      // 自分の宣言済み holes を差し引く。
      ui.Path effective = rawPaths[i];
      for (final hole in p.holes) {
        if (hole.length < 3) continue;
        effective = ui.Path.combine(
          ui.PathOperation.difference,
          effective,
          _ringToPath(hole),
        );
      }

      // ★ 実行時視覚的減算:
      // より新しいすべてのポリゴン Q の外周を、P から差し引く。
      // これで A∩B は常に A（新しい方）だけの色になる。
      for (int j = i + 1; j < sorted.length; j++) {
        effective = ui.Path.combine(
          ui.PathOperation.difference,
          effective,
          rawPaths[j],
        );
      }

      // パレット色（BGR / RGB 変換は color_extraction 側の定義に合わせる）
      final pc = (p.colorId >= 0 && p.colorId < colorPaletteBattle.length)
          ? colorPaletteBattle[p.colorId]
          : const ColorRGB(128, 128, 128);
      final isMine = myUid != null && p.ownerUid == myUid;

      // 塗り
      canvas.drawPath(
        effective,
        Paint()
          ..color = Color.fromRGBO(pc.r, pc.g, pc.b, isMine ? 0.42 : 0.30)
          ..style = PaintingStyle.fill,
      );

      // 枠線（減算後の実効領域の輪郭）
      canvas.drawPath(
        effective,
        Paint()
          ..color = Color.fromRGBO(pc.r, pc.g, pc.b, 1.0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isMine ? 3.0 : 1.5,
      );
    }
  }

  /// 単一リング(LatLng) → 閉じた screen-space ui.Path。
  ui.Path _ringToPath(List<LatLng> ring) {
    final path = ui.Path();
    if (ring.isEmpty) return path;
    final pts = ring.map(_toOffset).toList();
    path.moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path.close();
    return path;
  }

  Offset _toOffset(LatLng v) {
    final Point<double> sp = camera.latLngToScreenPoint(v);
    return Offset(sp.x, sp.y);
  }

  @override
  bool shouldRepaint(covariant _VersusPolygonsPainter old) =>
      old.camera.center != camera.center ||
      old.camera.zoom != camera.zoom ||
      old.camera.rotation != camera.rotation ||
      old.camera.nonRotatedSize != camera.nonRotatedSize ||
      old.myUid != myUid ||
      !listEquals(old.polygons, polygons);
}
