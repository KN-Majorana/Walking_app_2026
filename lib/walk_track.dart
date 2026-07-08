import 'package:latlong2/latlong.dart';

/// 散歩ルートの1点
class TrackPoint {
  final LatLng position;
  final DateTime timestamp;

  const TrackPoint({required this.position, required this.timestamp});

  Map<String, dynamic> toJson() => {
        'lat': position.latitude,
        'lng': position.longitude,
        'ts': timestamp.toIso8601String(),
      };

  factory TrackPoint.fromJson(Map<String, dynamic> json) => TrackPoint(
        position: LatLng(
          (json['lat'] as num).toDouble(),
          (json['lng'] as num).toDouble(),
        ),
        timestamp: DateTime.parse(json['ts'] as String),
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

  /// 終了時刻が設定されていない（記録中）なら true
  bool get isActive => endedAt == null;

  WalkTrack copyWith({
    DateTime? endedAt,
    List<TrackPoint>? points,
  }) =>
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
        id: json['id'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        endedAt: json['endedAt'] != null
            ? DateTime.parse(json['endedAt'] as String)
            : null,
        points: (json['points'] as List<dynamic>)
            .map((e) => TrackPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
