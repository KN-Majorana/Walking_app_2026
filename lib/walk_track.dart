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

  /// 記録中にカウントした歩数（再生時の統計表示に使う）。
  final int stepCount;

  const WalkTrack({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.points = const [],
    this.stepCount = 0,
  });

  /// 終了時刻が設定されていない（記録中）なら true
  bool get isActive => endedAt == null;

  /// 記録の所要時間（終了時刻が無ければ最後の点の時刻を使う）。
  Duration get duration {
    final end = endedAt ??
        (points.isNotEmpty ? points.last.timestamp : startedAt);
    return end.difference(startedAt);
  }

  /// 軌跡の合計距離（メートル）。連続する点の距離を積算する。
  double get totalDistanceMeters {
    if (points.length < 2) return 0;
    const distance = Distance(roundResult: false);
    var sum = 0.0;
    for (var i = 1; i < points.length; i++) {
      sum += distance(points[i - 1].position, points[i].position);
    }
    return sum;
  }

  WalkTrack copyWith({
    DateTime? endedAt,
    List<TrackPoint>? points,
    int? stepCount,
  }) =>
      WalkTrack(
        id: id,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        points: points ?? this.points,
        stepCount: stepCount ?? this.stepCount,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'points': points.map((p) => p.toJson()).toList(),
        'stepCount': stepCount,
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
        stepCount: (json['stepCount'] as num?)?.toInt() ?? 0,
      );
}
