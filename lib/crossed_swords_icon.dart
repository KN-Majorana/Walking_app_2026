import 'package:flutter/material.dart';

/// 剣が交差したマーク（対戦を表すアイコン）。
///
/// Material Icons には交差した剣のグリフが無いため、Tabler Icons の
/// "swords" と同じ形を 24x24 のグリッド上で線画として描く。
/// 線幅 2・端も角も丸め、[Icon] と同じ感覚でサイズと色だけを受け取る。
class CrossedSwordsIcon extends StatelessWidget {
  final double size;
  final Color color;

  /// true のとき、アイコンの上に斜線を重ねて「非表示中」を示す。
  final bool slashed;

  const CrossedSwordsIcon({
    super.key,
    this.size = 24,
    this.color = Colors.black87,
    this.slashed = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CrossedSwordsPainter(color: color, slashed: slashed),
      ),
    );
  }
}

class _CrossedSwordsPainter extends CustomPainter {
  final Color color;
  final bool slashed;

  const _CrossedSwordsPainter({required this.color, required this.slashed});

  @override
  void paint(Canvas canvas, Size size) {
    // 24x24 で設計し、実サイズへ拡大縮小する。
    final k = size.shortestSide / 24.0;
    canvas.save();
    canvas.scale(k);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // 右上から左下へ伸びる剣（刃）
    final bladeA = Path()
      ..moveTo(21, 3)
      ..lineTo(21, 8)
      ..lineTo(10, 17)
      ..lineTo(6, 21)
      ..lineTo(3, 18)
      ..lineTo(7, 14)
      ..lineTo(16, 3)
      ..close();

    // その剣の鍔
    final guardA = Path()
      ..moveTo(5, 13)
      ..lineTo(11, 19);

    // 左上から右下へ伸びる剣の柄側
    final hiltB = Path()
      ..moveTo(14.32, 17.32)
      ..lineTo(18, 21)
      ..lineTo(21, 18)
      ..lineTo(17.635, 14.635);

    // その剣の刃元
    final bladeB = Path()
      ..moveTo(10, 5.5)
      ..lineTo(8, 3)
      ..lineTo(3, 3)
      ..lineTo(3, 8)
      ..lineTo(6, 10.5);

    canvas
      ..drawPath(bladeA, stroke)
      ..drawPath(guardA, stroke)
      ..drawPath(hiltB, stroke)
      ..drawPath(bladeB, stroke);

    if (slashed) {
      // 斜線が剣と重なって潰れないよう、背景色で縁取ってから線を引く。
      canvas.drawLine(
        const Offset(3.5, 20.5),
        const Offset(20.5, 3.5),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CrossedSwordsPainter old) =>
      old.color != color || old.slashed != slashed;
}
