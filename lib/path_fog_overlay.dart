import 'dart:math' show cos, pow;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

const _deg2rad = 3.141592653589793 / 180;

/// 「マップ」モード用の霧オーバーレイ。
///
/// 地図全体を霧で覆い、[clearedPoints]（これまで歩いて通過した座標）の周辺
/// 半径 [clearRadiusMeters] だけを透明にする。コラージュモードのような
/// 色クラスタ／ポリゴン領域の概念は持たず、純粋に「通った場所が晴れる」だけ。
class PathFogOverlay extends StatelessWidget {
  final List<LatLng> clearedPoints;
  final Color fogColor;
  final double clearRadiusMeters;

  const PathFogOverlay({
    super.key,
    required this.clearedPoints,
    this.fogColor = const Color(0xCC000000),
    this.clearRadiusMeters = 40.0,
  });

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _PathFogPainter(
          camera: camera,
          clearedPoints: clearedPoints,
          fogColor: fogColor,
          clearRadiusMeters: clearRadiusMeters,
        ),
      ),
    );
  }
}

class _PathFogPainter extends CustomPainter {
  final MapCamera camera;
  final List<LatLng> clearedPoints;
  final Color fogColor;
  final double clearRadiusMeters;

  const _PathFogPainter({
    required this.camera,
    required this.clearedPoints,
    required this.fogColor,
    required this.clearRadiusMeters,
  });

  /// Web メルカトルでの「1ピクセルあたりのメートル」。タイルサイズ 256 前提。
  double _metersPerPixel(double latitude) {
    return 156543.03392 * cos(latitude * _deg2rad) / pow(2, camera.zoom);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;

    // 霧レイヤー（saveLayer で合成し、円を clear で抜く）
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = fogColor);

    final clearPaint = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    for (final p in clearedPoints) {
      final screen = camera.latLngToScreenPoint(p);
      final center = Offset(screen.x, screen.y);
      // 画面外は描画しない（半径ぶんの余裕を持たせて判定）
      final mpp = _metersPerPixel(p.latitude);
      if (mpp <= 0) continue;
      final radiusPx = clearRadiusMeters / mpp;
      if (center.dx < -radiusPx ||
          center.dy < -radiusPx ||
          center.dx > size.width + radiusPx ||
          center.dy > size.height + radiusPx) {
        continue;
      }
      canvas.drawCircle(center, radiusPx, clearPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PathFogPainter old) =>
      old.camera.center != camera.center ||
      old.camera.zoom != camera.zoom ||
      old.camera.rotation != camera.rotation ||
      old.camera.nonRotatedSize != camera.nonRotatedSize ||
      old.fogColor != fogColor ||
      old.clearRadiusMeters != clearRadiusMeters ||
      !listEquals(old.clearedPoints, clearedPoints);
}
