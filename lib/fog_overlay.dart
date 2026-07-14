import 'dart:math' show Point;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// 地図全体を霧で覆い、通過済み座標の周辺だけを透明にするレイヤー。
///
/// [FlutterMap.children] の最後に配置して使用する。
class FogOverlay extends StatelessWidget {
  final List<LatLng> clearedPoints;
  final double clearRadius;
  final Color fogColor;

  const FogOverlay({
    super.key,
    required this.clearedPoints,
    this.clearRadius = 30,
    this.fogColor = const Color(0xCC000000),
  }) : assert(clearRadius >= 0);

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);

    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _FogPainter(
          camera: camera,
          clearedPoints: clearedPoints,
          clearRadius: clearRadius,
          fogColor: fogColor,
        ),
      ),
    );
  }
}

class _FogPainter extends CustomPainter {
  static const Distance _distance = Distance(roundResult: false);

  final MapCamera camera;
  final List<LatLng> clearedPoints;
  final double clearRadius;
  final Color fogColor;

  const _FogPainter({
    required this.camera,
    required this.clearedPoints,
    required this.clearRadius,
    required this.fogColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;

    // BlendMode.clearを霧レイヤーだけに作用させるため、別レイヤーに描く。
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = fogColor);

    final clearPaint = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.fill;

    for (final point in clearedPoints) {
      final center = _toOffset(camera.latLngToScreenPoint(point));
      final radius = _radiusInPixels(point);

      // 画面外の円は描画しない。
      if (!_intersectsScreen(center, radius, size)) continue;

      canvas.drawCircle(center, radius, clearPaint);
    }

    canvas.restore();
  }

  double _radiusInPixels(LatLng center) {
    if (clearRadius == 0) return 0;

    final edge = _distance.offset(center, clearRadius, 180);
    final centerOffset = _toOffset(camera.latLngToScreenPoint(center));
    final edgeOffset = _toOffset(camera.latLngToScreenPoint(edge));
    return (centerOffset - edgeOffset).distance;
  }

  Offset _toOffset(Point<double> point) => Offset(point.x, point.y);

  bool _intersectsScreen(Offset center, double radius, Size size) {
    return center.dx + radius >= 0 &&
        center.dy + radius >= 0 &&
        center.dx - radius <= size.width &&
        center.dy - radius <= size.height;
  }

  @override
  bool shouldRepaint(covariant _FogPainter oldDelegate) {
    return oldDelegate.camera.center != camera.center ||
        oldDelegate.camera.zoom != camera.zoom ||
        oldDelegate.camera.rotation != camera.rotation ||
        oldDelegate.camera.nonRotatedSize != camera.nonRotatedSize ||
        oldDelegate.clearRadius != clearRadius ||
        oldDelegate.fogColor != fogColor ||
        !listEquals(oldDelegate.clearedPoints, clearedPoints);
  }
}
