import 'package:latlong2/latlong.dart';

import 'walk_track.dart';

/// 過去の[WalkTrack]を再生するためのゴースト位置計算クラス。
///
/// 経過時間を渡すと、その時刻に対応する軌跡上の位置を線形補間で返す。
/// タイマー管理は呼び出し側に任せて、ここは純粋計算だけを担当する。
class GhostTrack {
  final WalkTrack track;

  /// 再生速度の倍率。2.0なら2倍速、0.5なら半速。
  final double speed;

  GhostTrack(this.track, {this.speed = 1.0})
    : assert(speed > 0, '速度倍率は正の値を指定してください');

  /// 軌跡の実時間長(最初の点から最後の点まで)。
  Duration get duration {
    if (track.points.length < 2) return Duration.zero;
    return track.points.last.timestamp.difference(track.points.first.timestamp);
  }

  /// 速度倍率を考慮した再生時間。
  Duration get playbackDuration {
    if (duration == Duration.zero) return Duration.zero;
    return Duration(milliseconds: (duration.inMilliseconds / speed).round());
  }

  /// 再生終了したかどうか。
  bool isFinished(Duration elapsed) => elapsed >= playbackDuration;

  /// 再生開始からの経過時間に対応する位置を返す。
  ///
  /// 点が0個ならnull、1個なら常にその点、範囲外なら端の点を返す。
  /// 範囲内なら前後の[TrackPoint]を線形補間する。
  LatLng? positionAt(Duration elapsed) {
    if (track.points.isEmpty) return null;
    if (track.points.length == 1) return track.points.first.position;

    // 速度倍率を反映した軌跡上の時刻を求める。
    final firstTime = track.points.first.timestamp;
    final lastTime = track.points.last.timestamp;
    final trackElapsedMs = (elapsed.inMilliseconds * speed).round();
    final targetTime = firstTime.add(Duration(milliseconds: trackElapsedMs));

    if (!targetTime.isAfter(firstTime)) return track.points.first.position;
    if (!targetTime.isBefore(lastTime)) return track.points.last.position;

    // targetTimeを挟む2点を二分探索で取得する。
    var lo = 0;
    var hi = track.points.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) ~/ 2;
      if (track.points[mid].timestamp.isAfter(targetTime)) {
        hi = mid;
      } else {
        lo = mid;
      }
    }

    final a = track.points[lo];
    final b = track.points[hi];
    final spanMs = b.timestamp.difference(a.timestamp).inMilliseconds;
    if (spanMs <= 0) return a.position;

    final t = targetTime.difference(a.timestamp).inMilliseconds / spanMs;
    return LatLng(
      a.position.latitude + (b.position.latitude - a.position.latitude) * t,
      a.position.longitude + (b.position.longitude - a.position.longitude) * t,
    );
  }
}
