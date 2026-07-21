import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 現在地を示す青い丸マーカー。
///
/// [headingDegrees] を渡すと、Google Maps のように端末が向いている方向へ
/// 扇形のビームを描く。null（向き不明）のときは丸だけを表示する。
///
/// [mapRotationDegrees] は地図の回転角。地図を回した状態でも
/// ビームが実際の方位を指すよう、方位に足し込んで描画する。
///
/// ビームは与えられた領域いっぱいに広がるので、呼び出し側は
/// 丸より大きめの Marker（46x46 程度）を用意すること。丸の大きさは
/// [dotSize] で指定する。
class CurrentLocationMarker extends StatelessWidget {
  final double? headingDegrees;
  final double mapRotationDegrees;
  final double dotSize;

  const CurrentLocationMarker({
    super.key,
    this.headingDegrees,
    this.mapRotationDegrees = 0,
    this.dotSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: dotSize,
      height: dotSize,
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
    );

    if (headingDegrees == null) return Center(child: dot);

    // 画面上での向き。地図が回っている分を足す。
    final screenHeading = headingDegrees! + mapRotationDegrees;

    return Stack(
      alignment: Alignment.center,
      children: [
        // ビームは領域いっぱいに描く（Positioned.fill で制約を広げる）。
        Positioned.fill(
          child: Transform.rotate(
            angle: screenHeading * math.pi / 180,
            child: const CustomPaint(painter: _HeadingBeamPainter()),
          ),
        ),
        dot,
      ],
    );
  }
}

/// 上向き（0 度）の扇形ビーム。中心から外側に向けて薄くなる。
class _HeadingBeamPainter extends CustomPainter {
  const _HeadingBeamPainter();

  /// ビームの広がり（度）
  static const double _spreadDegrees = 60;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    if (radius <= 0) return;

    const spread = _spreadDegrees * math.pi / 180;
    // Canvas の 0 度は右方向なので、-90 度で真上になる
    final start = -math.pi / 2 - spread / 2;

    final rect = Rect.fromCircle(center: c, radius: radius);
    final path = Path()
      ..moveTo(c.dx, c.dy)
      ..arcTo(rect, start, spread, false)
      ..close();

    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.blue.withValues(alpha: 0.55),
          Colors.blue.withValues(alpha: 0.0),
        ],
      ).createShader(rect);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeadingBeamPainter oldDelegate) => false;
}
