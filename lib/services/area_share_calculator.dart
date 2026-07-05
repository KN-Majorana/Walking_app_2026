import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/polygon.dart';
import 'polygon_clip_service.dart';

/// リザルト画面の % バーで使う面積計算。
///
/// v4-1-2 で「盤面 F(bounding box) 基準」から
///   **「両者の実効面積比（合計 100%）」**
/// に変更した:
///   * `myPercent = S_self / (S_self + S_opp) * 100`
///   * `oppPercent = S_opp / (S_self + S_opp) * 100`
///   * 両者 0 の場合は 0% / 0% を返す。
///
/// また、Firestore 側の幾何減算が未反映のまま表示されるケースに備え、
/// 各ポリゴンの **実効面積** は
///   ( P の外周 − 宣言済み holes − P より新しい全ポリゴンの外周 )
/// で算出する。これで A∩B の面積は A 側にだけ計上され、B 側では
/// 二重計上されない。
class AreaShareCalculator {
  AreaShareCalculator._();

  static const double _mPerDegLat = 111320.0;

  /// [polygons] を対象に、[myUid] と [oppUid] の面積シェア（%）を返す。
  static AreaShareResult compute({
    required List<WalkPolygon> polygons,
    required String myUid,
    required String oppUid,
  }) {
    final live = polygons
        .where((p) => p.isActive && p.vertices.length >= 3 && p.confirmed)
        .toList()
      ..sort((a, b) {
        // 塗り合いの上下関係と一致させるため claimStamp で並べる。
        final aT = a.claimStamp?.millisecondsSinceEpoch ?? 0;
        final bT = b.claimStamp?.millisecondsSinceEpoch ?? 0;
        return aT.compareTo(bT);
      });

    if (live.isEmpty) {
      return const AreaShareResult(myPercent: 0.0, opponentPercent: 0.0);
    }

    // 参照緯度（cos(lat) 補正の基準）
    double sumLat = 0.0;
    int cnt = 0;
    for (final p in live) {
      for (final v in p.vertices) {
        sumLat += v.latitude;
        cnt++;
      }
    }
    final refLat = cnt > 0 ? sumLat / cnt : 0.0;

    double mySum = 0.0, oppSum = 0.0;
    for (int i = 0; i < live.length; i++) {
      final p = live[i];
      // (1) 外周から自身の holes を引く
      double a = _polyArea(p.vertices, refLat);
      for (final h in p.holes) {
        if (h.length >= 3) a -= _polyArea(h, refLat);
      }
      // (2) P より新しいすべての Q との重なり面積を差し引く（視覚と一致させる）
      for (int j = i + 1; j < live.length; j++) {
        final q = live[j];
        final overlap = _overlapArea(p.vertices, q.vertices, refLat);
        a -= overlap;
      }
      if (a < 0) a = 0.0;

      if (p.ownerUid == myUid) {
        mySum += a;
      } else if (p.ownerUid == oppUid) {
        oppSum += a;
      }
    }

    final total = mySum + oppSum;
    if (total <= 0) {
      return const AreaShareResult(myPercent: 0.0, opponentPercent: 0.0);
    }
    final my = mySum / total * 100.0;
    final opp = oppSum / total * 100.0;
    return AreaShareResult(myPercent: my, opponentPercent: opp);
  }

  /// P と Q の重なり領域（P ∩ Q）の面積。
  /// PolygonClipService.classify を使い、P − Q の結果から
  /// overlap = area(P) − area(P − Q) を求める。
  static double _overlapArea(
    List<LatLng> pRing,
    List<LatLng> qRing,
    double refLat,
  ) {
    if (pRing.length < 3 || qRing.length < 3) return 0.0;
    if (!PolygonClipService.regionsOverlap(pRing, qRing)) return 0.0;
    final outcome = PolygonClipService.classify(pRing, qRing);
    final pArea = _polyArea(pRing, refLat);
    switch (outcome.kind) {
      case SubtractKind.unchanged:
        return 0.0;
      case SubtractKind.consumed:
        return pArea; // 完全に Q に取られた
      case SubtractKind.updatedSingle:
        return pArea - _polyArea(outcome.single!, refLat);
      case SubtractKind.holed:
        return _polyArea(outcome.hole!, refLat);
      case SubtractKind.split:
        double rest = 0.0;
        for (final r in outcome.pieces!) {
          rest += _polyArea(r, refLat);
        }
        return pArea - rest;
    }
  }

  static double _polyArea(List<LatLng> verts, double refLat) {
    if (verts.length < 3) return 0.0;
    final mPerLng = _mPerDegLat * math.cos(refLat * math.pi / 180.0);
    double sum = 0.0;
    for (int i = 0; i < verts.length; i++) {
      final a = verts[i];
      final b = verts[(i + 1) % verts.length];
      final ax = a.longitude * mPerLng;
      final ay = a.latitude * _mPerDegLat;
      final bx = b.longitude * mPerLng;
      final by = b.latitude * _mPerDegLat;
      sum += ax * by - bx * ay;
    }
    return sum.abs() / 2.0;
  }
}

class AreaShareResult {
  final double myPercent;
  final double opponentPercent;
  const AreaShareResult({
    required this.myPercent,
    required this.opponentPercent,
  });
}
