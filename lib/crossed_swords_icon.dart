import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 剣が交差したマーク（対戦を表すアイコン）。
///
/// Material Icons には交差した剣のグリフが無いため、自前で描画する。
/// [Icon] と同じ感覚で使えるよう、サイズと色だけを受け取る。
class CrossedSwordsIcon extends StatelessWidget {
  final double size;
  final Color color;

  const CrossedSwordsIcon({
    super.key,
    this.size = 24,
    this.color = Colors.black87,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CrossedSwordsPainter(color: color),
      ),
    );
  }
}

class _CrossedSwordsPainter extends CustomPainter {
  final Color color;

  const _CrossedSwordsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    // 24px を基準に設計し、実サイズへ拡大縮小する。
    final k = s / 24.0;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(k);

    // 剣 1 本を「下から上へ伸びる」形で描き、左右に傾けて交差させる。
    void sword() {
      // 刃
      stroke.strokeWidth = 2.2;
      canvas.drawLine(const Offset(0, 3), const Offset(0, -10), stroke);
      // 切先
      final tip = Path()
        ..moveTo(-1.6, -8.4)
        ..lineTo(0, -11.2)
        ..lineTo(1.6, -8.4);
      canvas.drawPath(tip, stroke..strokeWidth = 1.6);
      // 鍔（つば）
      canvas.drawLine(const Offset(-3.4, 3), const Offset(3.4, 3), stroke);
      // 柄
      stroke.strokeWidth = 2.0;
      canvas.drawLine(const Offset(0, 3), const Offset(0, 8.4), stroke);
      // 柄頭
      stroke.strokeWidth = 1.8;
      canvas.drawLine(const Offset(-1.8, 9.4), const Offset(1.8, 9.4), stroke);
    }

    // 右上がりの剣
    canvas.save();
    canvas.rotate(math.pi / 5.2);
    sword();
    canvas.restore();

    // 左上がりの剣
    canvas.save();
    canvas.rotate(-math.pi / 5.2);
    sword();
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CrossedSwordsPainter old) =>
      old.color != color;
}
