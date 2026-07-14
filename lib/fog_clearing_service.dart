import 'package:latlong2/latlong.dart';

import 'walk_track.dart';

/// 軌跡の周辺で霧が晴れているかを判定する計算サービス。
///
/// 描画やデータ保存は行わず、座標間の距離計算だけを担当する。
class FogClearingService {
  FogClearingService._();

  static const Distance _distance = Distance(roundResult: false);

  /// [point] がいずれかの軌跡点から [radius] メートル以内なら true。
  static bool isCleared(
    LatLng point,
    Iterable<LatLng> trackPoints, {
    double radius = 30,
  }) {
    if (radius < 0) {
      throw ArgumentError.value(radius, 'radius', '0以上を指定してください');
    }

    return trackPoints.any(
      (trackPoint) => _distance(point, trackPoint) <= radius,
    );
  }

  /// [WalkTrack] を直接渡して霧が晴れているかを判定する。
  static bool isClearedByTrack(
    LatLng point,
    WalkTrack track, {
    double radius = 30,
  }) {
    return isCleared(
      point,
      track.points.map((trackPoint) => trackPoint.position),
      radius: radius,
    );
  }

  /// 複数の散歩記録から、霧晴らし描画に使う座標を取り出す。
  static List<LatLng> clearedPointsFromTracks(Iterable<WalkTrack> tracks) {
    return [
      for (final track in tracks)
        for (final point in track.points) point.position,
    ];
  }
}
