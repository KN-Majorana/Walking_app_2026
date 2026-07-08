import 'package:latlong2/latlong.dart';
import 'walk_track.dart';

/// 過去の散歩記録を任意の速度で再生するクラス
class GhostTrack {
  final WalkTrack track;
  final double speed;

  GhostTrack(this.track, {this.speed = 1.0});

  /// 軌跡全体の実際の経過時間
  Duration get _totalDuration {
    if (track.points.length < 2) return Duration.zero;
    return track.points.last.timestamp
        .difference(track.points.first.timestamp);
  }

  /// [realElapsed] の実時間で再生が終わっているか
  bool isFinished(Duration realElapsed) {
    final simMicros = (realElapsed.inMicroseconds * speed).round();
    return simMicros >= _totalDuration.inMicroseconds;
  }

  /// [realElapsed] の実時間に対応する補間済み位置を返す
  LatLng? positionAt(Duration realElapsed) {
    final pts = track.points;
    if (pts.isEmpty) return null;
    if (pts.length == 1) return pts.first.position;

    final simMicros = (realElapsed.inMicroseconds * speed).round();
    final startTime = pts.first.timestamp;
    final targetTime = startTime.add(Duration(microseconds: simMicros));

    for (int i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      if (!targetTime.isAfter(b.timestamp)) {
        final segMicros = b.timestamp.difference(a.timestamp).inMicroseconds;
        if (segMicros == 0) return a.position;
        final t =
            targetTime.difference(a.timestamp).inMicroseconds / segMicros;
        return LatLng(
          a.position.latitude +
              (b.position.latitude - a.position.latitude) * t,
          a.position.longitude +
              (b.position.longitude - a.position.longitude) * t,
        );
      }
    }
    return pts.last.position;
  }
}
