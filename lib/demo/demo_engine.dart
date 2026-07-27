import 'package:latlong2/latlong.dart';

import '../battle/models/polygon.dart';
import 'demo_config.dart';

/// デモ用の写真ピン（実カメラ・色判定を使わない簡易モデル）。
/// 画像はアセット（assets/demo_photos/*.png）で保持する。
class DemoPin {
  final String id;
  final LatLng position;
  final String asset;
  final int colorId;
  final String ownerUid;

  const DemoPin({
    required this.id,
    required this.position,
    required this.asset,
    required this.colorId,
    required this.ownerUid,
  });
}

/// スケジュール上の 1 イベント（ある座標に到達して写真ピンを刺す瞬間）。
class DemoEvent {
  final double timeSec;
  final String ownerUid;
  final int waypointIndex; // 0..2
  final String asset;
  final int colorId;

  const DemoEvent({
    required this.timeSec,
    required this.ownerUid,
    required this.waypointIndex,
    required this.asset,
    required this.colorId,
  });

  bool get isChallenger => ownerUid == DemoConfig.challengerUid;

  /// 「赤 1枚目」等の見出し。
  String get label {
    final who = isChallenger ? '青(challenger)' : '赤(opponent)';
    return '$who ${waypointIndex + 1}枚目';
  }
}

/// 対戦デモの状態を「経過デモ秒」から純粋に導出するエンジン。
///
/// 位置・ピン・多角形はすべて時刻 t の関数として計算できるので、
/// 再生速度を変えても（t の進め方を変えるだけで）破綻しない。
/// カメラ起動オーバーレイなどの一過性の演出だけは、画面側で
/// 「まだ発火していないイベントを跨いだ瞬間」に処理する。
class DemoEngine {
  DemoEngine._();

  /// claimStamp 用の基準時刻。相対順序だけ意味を持つ。
  /// 到達秒をそのままミリ秒エポックに載せる（red_3=720s < blue_3=840s）。
  static DateTime _stamp(double sec) =>
      DateTime.fromMillisecondsSinceEpoch((sec * 1000).round());

  /// 全イベントを到達時刻の昇順で返す
  /// （red_1 → blue_1 → red_2 → blue_2 → red_3 → blue_3）。
  static List<DemoEvent> buildEvents() {
    final events = <DemoEvent>[];
    for (int i = 0; i < 3; i++) {
      events.add(DemoEvent(
        timeSec: DemoConfig.opponentArrivalSec[i],
        ownerUid: DemoConfig.opponentUid,
        waypointIndex: i,
        asset: DemoConfig.opponentPhotos[i],
        colorId: DemoConfig.opponentColorId,
      ));
      events.add(DemoEvent(
        timeSec: DemoConfig.challengerArrivalSec[i],
        ownerUid: DemoConfig.challengerUid,
        waypointIndex: i,
        asset: DemoConfig.challengerPhotos[i],
        colorId: DemoConfig.challengerColorId,
      ));
    }
    events.sort((a, b) => a.timeSec.compareTo(b.timeSec));
    return events;
  }

  /// 時刻 t（デモ秒）における対決終了時刻。
  /// challenger が 3 枚目を刺した時刻 + 待ち時間。
  static double get endSec =>
      DemoConfig.challengerArrivalSec.last + DemoConfig.endDelayAfterLastSec;

  /// あるプレイヤーの時刻 t における位置。
  /// start → p0 → p1 → p2 と線形補間し、3 枚目到達後は p2 で停止する。
  static LatLng positionOf({
    required List<LatLng> route,
    required List<double> arrivals,
    required double t,
  }) {
    if (t <= 0) return DemoConfig.start;
    // セグメント境界: 0, arrivals[0], arrivals[1], arrivals[2]
    final pts = <LatLng>[DemoConfig.start, ...route];
    final times = <double>[0, ...arrivals];
    for (int i = 0; i < times.length - 1; i++) {
      final t0 = times[i];
      final t1 = times[i + 1];
      if (t <= t1) {
        final f = t1 <= t0 ? 1.0 : ((t - t0) / (t1 - t0)).clamp(0.0, 1.0);
        return _lerp(pts[i], pts[i + 1], f);
      }
    }
    return pts.last; // 到達後は停止
  }

  static LatLng _lerp(LatLng a, LatLng b, double f) => LatLng(
        a.latitude + (b.latitude - a.latitude) * f,
        a.longitude + (b.longitude - a.longitude) * f,
      );

  static LatLng challengerPosition(double t) => positionOf(
        route: DemoConfig.challengerRoute,
        arrivals: DemoConfig.challengerArrivalSec,
        t: t,
      );

  static LatLng opponentPosition(double t) => positionOf(
        route: DemoConfig.opponentRoute,
        arrivals: DemoConfig.opponentArrivalSec,
        t: t,
      );

  /// 時刻 t までに刺された全ピン。
  static List<DemoPin> pinsAt(double t) {
    final pins = <DemoPin>[];
    for (int i = 0; i < 3; i++) {
      if (t >= DemoConfig.opponentArrivalSec[i]) {
        pins.add(DemoPin(
          id: 'opp_$i',
          position: DemoConfig.opponentRoute[i],
          asset: DemoConfig.opponentPhotos[i],
          colorId: DemoConfig.opponentColorId,
          ownerUid: DemoConfig.opponentUid,
        ));
      }
      if (t >= DemoConfig.challengerArrivalSec[i]) {
        pins.add(DemoPin(
          id: 'cha_$i',
          position: DemoConfig.challengerRoute[i],
          asset: DemoConfig.challengerPhotos[i],
          colorId: DemoConfig.challengerColorId,
          ownerUid: DemoConfig.challengerUid,
        ));
      }
    }
    return pins;
  }

  /// 時刻 t における確定多角形（3 枚目まで刺されたら三角形が確定）。
  /// claimStamp（＝ claimedAt）が新しい方が前面に来て、重なりを塗り返す。
  static List<WalkPolygon> polygonsAt(double t) {
    final polys = <WalkPolygon>[];
    // 赤（opponent）：3 枚目到達で確定
    final oppLast = DemoConfig.opponentArrivalSec.last;
    if (t >= oppLast) {
      polys.add(WalkPolygon(
        id: 'poly_opponent',
        ownerUid: DemoConfig.opponentUid,
        ownerName: '赤(opponent)',
        colorId: DemoConfig.opponentColorId,
        vertices: List<LatLng>.from(DemoConfig.opponentRoute),
        createdAt: _stamp(oppLast),
        claimedAt: _stamp(oppLast),
        photoIds: const ['opp_0', 'opp_1', 'opp_2'],
        confirmed: true,
      ));
    }
    // 青（challenger）：3 枚目到達で確定（赤より後 → 前面）
    final chaLast = DemoConfig.challengerArrivalSec.last;
    if (t >= chaLast) {
      polys.add(WalkPolygon(
        id: 'poly_challenger',
        ownerUid: DemoConfig.challengerUid,
        ownerName: '青(challenger)',
        colorId: DemoConfig.challengerColorId,
        vertices: List<LatLng>.from(DemoConfig.challengerRoute),
        createdAt: _stamp(chaLast),
        claimedAt: _stamp(chaLast),
        photoIds: const ['cha_0', 'cha_1', 'cha_2'],
        confirmed: true,
      ));
    }
    return polys;
  }
}
