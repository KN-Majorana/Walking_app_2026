import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 地図の右上に置く小さなコンパス。
///
/// [rotationDegrees] は地図の回転角（flutter_map の `camera.rotation`）。
/// 針は「北がどちらか」を指すので、地図と同じ向きに回す。
/// タップすると北を上に戻す（[onTap]）。
class MapCompass extends StatelessWidget {
  final double rotationDegrees;
  final VoidCallback? onTap;
  final double size;

  const MapCompass({
    super.key,
    required this.rotationDegrees,
    this.onTap,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Transform.rotate(
            angle: rotationDegrees * math.pi / 180,
            child: CustomPaint(painter: const _CompassPainter()),
          ),
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  const _CompassPainter();

  /// 北を指す赤い針
  static const _north = Color(0xFFD32F2F);

  /// 南を指す灰色の針
  static const _south = Color(0xFF9E9E9E);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;

    // 針は上下対称の細いひし形を 2 つ（北=赤 / 南=灰）
    final needleHalfWidth = r * 0.22;
    final needleLength = r * 0.62;

    final north = Path()
      ..moveTo(c.dx, c.dy - needleLength)
      ..lineTo(c.dx - needleHalfWidth, c.dy)
      ..lineTo(c.dx + needleHalfWidth, c.dy)
      ..close();

    final south = Path()
      ..moveTo(c.dx, c.dy + needleLength)
      ..lineTo(c.dx - needleHalfWidth, c.dy)
      ..lineTo(c.dx + needleHalfWidth, c.dy)
      ..close();

    canvas
      ..drawPath(north, Paint()..color = _north)
      ..drawPath(south, Paint()..color = _south);

    // 「N」の代わりに、上端へ小さな目印を置く（文字は小さすぎて潰れるため）
    canvas.drawCircle(
      Offset(c.dx, c.dy - r * 0.82),
      r * 0.07,
      Paint()..color = _north,
    );
  }

  @override
  bool shouldRepaint(covariant _CompassPainter oldDelegate) => false;
}
