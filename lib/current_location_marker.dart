import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 現在地を示す青い丸マーカー。
///
/// [headingDegrees] を渡すと、Google Maps のように端末が向いている方向へ
/// 扇形のビームを描く。null（向き不明）のときは丸だけを表示する。
///
/// ビームの角度は端末の方位（真北基準・0度＝北）だけで指定する。
/// 地図回転の補正はここでは行わず、呼び出し側の Marker を
/// `rotate: false`（地図と一緒に回る）にしておくこと。こうすると
/// マーカーのローカル上方向が常に「地図上の北（＝実世界の北）」に一致し、
/// ビームは実世界で端末が向いている方角を、地図上の正しい向きで指す。
/// 地図を回すとビームも一緒に回り（実世界の方角は不変）、端末を回すと
/// ビームが動く。
///
/// ビームは与えられた領域いっぱいに広がるので、呼び出し側は
/// 丸より大きめの Marker（46x46 程度）を用意すること。丸の大きさは
/// [dotSize] で指定する。
class CurrentLocationMarker extends StatelessWidget {
  final double? headingDegrees;
  final double dotSize;

  const CurrentLocationMarker({
    super.key,
    this.headingDegrees,
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

    // ビームの向きは端末の方位のみで決まる（呼び出し側の Marker が
    // rotate: false で地図と一緒に回るため、ここでは地図の回転角を
    // 足し込まない）。0 度＝マーカーのローカル上方向＝地図上の北。
    final screenHeading = headingDegrees!;

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
