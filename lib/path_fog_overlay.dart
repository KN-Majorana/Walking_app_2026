import 'dart:math' show cos, pow;
import 'dart:ui' as ui show Gradient;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import 'fog_texture.dart';

const _deg2rad = 3.141592653589793 / 180;

/// 「マップ」モード用の霧オーバーレイ。
///
/// 地図全体を霧で覆い、[clearedPoints]（これまで歩いて通過した座標）の周辺
/// 半径 [clearRadiusMeters] だけを透明にする。コラージュモードのような
/// 色クラスタ／ポリゴン領域の概念は持たず、純粋に「通った場所が晴れる」だけ。
///
/// 晴れ方は 2 段階になっている:
///   * 中心から [fullClearRadiusMeters] までは完全に透明
///   * そこから [clearRadiusMeters] にかけて、霧が徐々に濃くなる
/// これにより、円の輪郭がくっきり出ずに霧へなじむ。
class PathFogOverlay extends StatelessWidget {
  final List<LatLng> clearedPoints;
  final Color fogColor;

  /// 霧が完全に消える半径（メートル）。この外側は元の濃さに戻る。
  final double clearRadiusMeters;

  /// 完全に透明になる内側の半径（メートル）。
  /// [clearRadiusMeters] との差がグラデーションの幅になる。
  final double fullClearRadiusMeters;

  const PathFogOverlay({
    super.key,
    required this.clearedPoints,
    this.fogColor = const Color(0xFFF4F6F9),
    this.clearRadiusMeters = 40.0,
    this.fullClearRadiusMeters = 30.0,
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
          fullClearRadiusMeters: fullClearRadiusMeters,
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
  final double fullClearRadiusMeters;

  const _PathFogPainter({
    required this.camera,
    required this.clearedPoints,
    required this.fogColor,
    required this.clearRadiusMeters,
    required this.fullClearRadiusMeters,
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
    final tex = FogTexture.image;
    if (tex != null) {
      canvas.drawImageRect(
        tex,
        Rect.fromLTWH(0, 0, tex.width.toDouble(), tex.height.toDouble()),
        bounds,
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      canvas.drawRect(bounds, Paint()..color = fogColor);
    }

    // 晴れている場所を抜く。内側は完全に透明、外周に向けて徐々に霧へ戻す。
    // BlendMode.clear はペイントのアルファ分だけ消すので、
    // 放射状グラデーション（中心=不透明 → 外周=透明）で境界をぼかせる。
    final clearPaint = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // グラデーションが始まる位置（0.0〜1.0）。
    // 例: 25m / 30m なら 0.833 から外側だけがぼける。
    final innerStop = clearRadiusMeters <= 0
        ? 1.0
        : (fullClearRadiusMeters / clearRadiusMeters).clamp(0.0, 1.0);

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

      if (innerStop >= 1.0) {
        // グラデーション幅ゼロ → 従来どおりの単純な円
        clearPaint.shader = null;
        canvas.drawCircle(center, radiusPx, clearPaint);
        continue;
      }

      clearPaint.shader = ui.Gradient.radial(
        center,
        radiusPx,
        const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        [innerStop, 1.0],
      );
      canvas.drawCircle(center, radiusPx, clearPaint);
    }
    clearPaint.shader = null;

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
      old.fullClearRadiusMeters != fullClearRadiusMeters ||
      !listEquals(old.clearedPoints, clearedPoints);
}
