import 'package:flutter/material.dart';

/// Splatoon 風の面積比バー。自分（左）と相手（右）の塗り率を横帯で表示する。
///
/// 使い方は末尾のプレビュー例を参照。
class AreaShareBar extends StatelessWidget {
  final Color myColor;
  final Color opponentColor;
  final double myPercent;
  final double opponentPercent;

  /// 帯の高さ（フォントに合わせて自動調整可能）
  final double height;

  const AreaShareBar({
    super.key,
    required this.myColor,
    required this.opponentColor,
    required this.myPercent,
    required this.opponentPercent,
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    final total = (myPercent + opponentPercent).clamp(0.0, 100.0);
    // 未塗り部分（total < 100）を中央にグレー帯として挟む
    final myFlex = (myPercent * 10).round().clamp(0, 1000);
    final oppFlex = (opponentPercent * 10).round().clamp(0, 1000);
    final gapFlex = ((100.0 - total) * 10).round().clamp(0, 1000);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              // 自分側（左）
              if (myFlex > 0)
                Expanded(
                  flex: myFlex,
                  child: Container(
                    color: myColor,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _Label(
                      text: '${myPercent.toStringAsFixed(1)}%',
                      align: TextAlign.left,
                    ),
                  ),
                ),
              // 中央の未塗りギャップ
              if (gapFlex > 0)
                Expanded(
                  flex: gapFlex,
                  child: Container(color: const Color(0xFFE0E0E0)),
                ),
              // 相手側（右）
              if (oppFlex > 0)
                Expanded(
                  flex: oppFlex,
                  child: Container(
                    color: opponentColor,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _Label(
                      text: '${opponentPercent.toStringAsFixed(1)}%',
                      align: TextAlign.right,
                    ),
                  ),
                ),
              // 全部 0 のフォールバック（幅を持たせるための最小体裁）
              if (myFlex == 0 && oppFlex == 0 && gapFlex == 0)
                Expanded(
                  child: Container(color: const Color(0xFFE0E0E0)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final TextAlign align;
  const _Label({required this.text, required this.align});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: align,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 16,
        shadows: [
          Shadow(color: Colors.black45, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
    );
  }
}

// ── プレビュー用の使用例 ──────────────────────────────
//
// AreaShareBar(
//   myColor: Colors.orange,
//   opponentColor: Colors.blue,
//   myPercent: 42.6,
//   opponentPercent: 37.1,
// );
//
// active 中でも同じ Widget を上部に置くだけで動く（再計算のトリガは呼び出し側）。
