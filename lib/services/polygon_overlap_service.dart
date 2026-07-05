import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/polygon.dart';

/// 多角形の幾何計算（凸包・交差・面積・実効面積）を担うサービス。
///
/// すべて純 Dart 実装。座標は (経度=x, 緯度=y) の平面として扱い、
/// 面積のみ緯度補正したメートル換算（簡易な正距円筒近似）で算出する。
class PolygonOverlapService {
  PolygonOverlapService._();

  static const double _metersPerDegLat = 111320.0;

  // ─────────────────────────────────────────
  // 凸包（Andrew's monotone chain）
  // ─────────────────────────────────────────

  /// 緯度経度の点群から凸包頂点列（反時計回り）を返す。
  static List<LatLng> convexHull(List<LatLng> points) {
    if (points.length < 3) return List<LatLng>.from(points);

    final pts = List<LatLng>.from(points)
      ..sort((a, b) => a.longitude != b.longitude
          ? a.longitude.compareTo(b.longitude)
          : a.latitude.compareTo(b.latitude));

    double cross(LatLng o, LatLng a, LatLng b) =>
        (a.longitude - o.longitude) * (b.latitude - o.latitude) -
        (a.latitude - o.latitude) * (b.longitude - o.longitude);

    final lower = <LatLng>[];
    for (final p in pts) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    final upper = <LatLng>[];
    for (final p in pts.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  // ─────────────────────────────────────────
  // 面積（平方メートル）
  // ─────────────────────────────────────────

  /// 多角形の面積を平方メートルで返す（緯度補正つき正距円筒近似）。
  static double areaMeters(List<LatLng> verts) {
    if (verts.length < 3) return 0.0;

    final refLat =
        verts.map((v) => v.latitude).reduce((a, b) => a + b) / verts.length;
    final mPerLng = _metersPerDegLat * math.cos(refLat * math.pi / 180.0);

    double sum = 0.0;
    for (int i = 0; i < verts.length; i++) {
      final a = verts[i];
      final b = verts[(i + 1) % verts.length];
      final ax = a.longitude * mPerLng;
      final ay = a.latitude * _metersPerDegLat;
      final bx = b.longitude * mPerLng;
      final by = b.latitude * _metersPerDegLat;
      sum += ax * by - bx * ay;
    }
    return sum.abs() / 2.0;
  }

  // ─────────────────────────────────────────
  // 凸多角形どうしの交差（Sutherland–Hodgman）
  // ─────────────────────────────────────────

  /// subject を凸多角形 clip でクリップした交差ポリゴンを返す。
  /// clip は凸であることを前提とする（凸包なので常に成立）。
  /// 交差が空の場合は空リスト。
  static List<LatLng> intersectConvex(
    List<LatLng> subject,
    List<LatLng> clip,
  ) {
    if (subject.length < 3 || clip.length < 3) return const [];

    var output = List<LatLng>.from(subject);
    final c = _ensureCcw(clip);

    for (int i = 0; i < c.length; i++) {
      if (output.isEmpty) break;
      final a = c[i];
      final b = c[(i + 1) % c.length];
      final input = output;
      output = <LatLng>[];

      for (int j = 0; j < input.length; j++) {
        final cur = input[j];
        final prev = input[(j - 1 + input.length) % input.length];
        final curIn = _isLeft(a, b, cur) >= 0;
        final prevIn = _isLeft(a, b, prev) >= 0;

        if (curIn) {
          if (!prevIn) output.add(_lineIntersect(prev, cur, a, b));
          output.add(cur);
        } else if (prevIn) {
          output.add(_lineIntersect(prev, cur, a, b));
        }
      }
    }
    return output;
  }

  /// 2 つの多角形の交差面積（平方メートル）。
  static double intersectionAreaMeters(
    List<LatLng> a,
    List<LatLng> b,
  ) {
    final inter = intersectConvex(a, b);
    if (inter.length < 3) return 0.0;
    return areaMeters(inter);
  }

  // ─────────────────────────────────────────
  // 実効面積（機能2の上書きを反映）
  // ─────────────────────────────────────────

  /// [target] の「実効的に見えている」面積を返す。
  ///
  /// [all] のうち [target] より createdAt が新しい多角形によって
  /// 上書きされた領域を差し引く。重なり合う複数の新しい多角形による
  /// 二重控除を避けるため、控除量は target 自身の面積で上限クランプする
  /// （簡易実装：仕様で許容）。
  static double effectiveAreaMeters(
    WalkPolygon target,
    List<WalkPolygon> all,
  ) {
    final base = areaMeters(target.vertices);
    if (base <= 0) return 0.0;
    final tCreated = target.claimStamp;
    if (tCreated == null) return base; // 未確定は面積0扱いが妥当だが安全側でbase

    double overlap = 0.0;
    for (final other in all) {
      if (other.id == target.id) continue;
      if (!other.confirmed) continue;
      final oCreated = other.claimStamp;
      if (oCreated == null) continue;
      // other の方が新しく主張された場合のみ上書きされる
      if (!oCreated.isAfter(tCreated)) continue;
      overlap += intersectionAreaMeters(target.vertices, other.vertices);
    }

    final effective = base - overlap;
    return effective < 0 ? 0.0 : effective;
  }

  // ─────────────────────────────────────────
  // 内部ヘルパー
  // ─────────────────────────────────────────

  /// 辺 a→b に対する点 p の符号付き左側判定（外積）。x=lng, y=lat。
  static double _isLeft(LatLng a, LatLng b, LatLng p) =>
      (b.longitude - a.longitude) * (p.latitude - a.latitude) -
      (b.latitude - a.latitude) * (p.longitude - a.longitude);

  /// 直線 a→b と線分 p1→p2 の交点。
  static LatLng _lineIntersect(LatLng p1, LatLng p2, LatLng a, LatLng b) {
    final x1 = p1.longitude, y1 = p1.latitude;
    final x2 = p2.longitude, y2 = p2.latitude;
    final x3 = a.longitude, y3 = a.latitude;
    final x4 = b.longitude, y4 = b.latitude;

    final denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
    if (denom.abs() < 1e-12) return p2; // ほぼ平行：安全側で端点を返す

    final t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / denom;
    return LatLng(y1 + t * (y2 - y1), x1 + t * (x2 - x1));
  }

  /// 反時計回りに揃える（符号付き面積で判定）。
  static List<LatLng> _ensureCcw(List<LatLng> poly) {
    double sum = 0.0;
    for (int i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      sum += (b.longitude - a.longitude) * (b.latitude + a.latitude);
    }
    // sum > 0 は時計回り（画面座標系ではないので符号は緯度経度基準）
    return sum > 0 ? poly.reversed.toList() : poly;
  }
}
