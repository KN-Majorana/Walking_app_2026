import 'package:latlong2/latlong.dart';

/// 軌跡上の1点(座標 + 時刻)
class TrackPoint {
  final LatLng position;
  final DateTime timestamp;

  const TrackPoint({required this.position, required this.timestamp});

  Map<String, dynamic> toJson() => {
    'lat': position.latitude,
    'lng': position.longitude,
    'time': timestamp.toIso8601String(),
  };

  factory TrackPoint.fromJson(Map<String, dynamic> json) => TrackPoint(
    position: LatLng(json['lat'], json['lng']),
    timestamp: DateTime.parse(json['time']),
  );
}

/// 1回の散歩記録
class WalkTrack {
  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final List<TrackPoint> points;

  const WalkTrack({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.points = const [],
  });

  /// 記録中かどうか(終了時刻が未設定なら記録中)
  bool get isActive => endedAt == null;

  WalkTrack copyWith({DateTime? endedAt, List<TrackPoint>? points}) =>
      WalkTrack(
        id: id,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        points: points ?? this.points,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'points': points.map((p) => p.toJson()).toList(),
  };

  factory WalkTrack.fromJson(Map<String, dynamic> json) => WalkTrack(
    id: json['id'],
    startedAt: DateTime.parse(json['startedAt']),
    endedAt: json['endedAt'] != null ? DateTime.parse(json['endedAt']) : null,
    points: (json['points'] as List)
        .map((p) => TrackPoint.fromJson(p))
        .toList(),
  );
}
