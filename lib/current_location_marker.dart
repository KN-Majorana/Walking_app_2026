import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 現在地を示す青い丸マーカー。
///
/// [headingDegrees] を渡すと、Google Maps のように端末が向いている方向へ
/// 扇形のビームを描く。null（向き不明）のときは従来どおり丸だけを表示する。
///
/// [mapRotationDegrees] は地図の回転角。地図を回した状態でも
/// ビームが実際の方位を指すよう、方位から差し引いて描画する。
class CurrentLocationMarker extends StatelessWidget {
  final double? headingDegrees;
  final double mapRotationDegrees;

  const CurrentLocationMarker({
    super.key,
    this.headingDegrees,
    this.mapRotationDegrees = 0,
  });

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
    );

    if (headingDegrees == null) return dot;

    // 画面上での向き。地図が回っている分を差し引く。
    final screenHeading = headingDegrees! + mapRotationDegrees;

    // ビームは丸より大きく描くので、はみ出しを許可する Stack で重ねる。
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned(
          child: Transform.rotate(
            angle: screenHeading * math.pi / 180,
            child: CustomPaint(
              size: const Size(46, 46),
              painter: const _HeadingBeamPainter(),
            ),
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

    const spread = _spreadDegrees * math.pi / 180;
    // -90 度で真上（Canvas の 0 度は右方向のため）
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
