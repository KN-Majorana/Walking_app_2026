import 'package:flutter/material.dart';

/// 相手プレイヤーの最新位置を示すマーカー。
///
/// 自分の現在地（青い丸）と区別できるよう、相手の色の縁取りをした
/// 人型アイコンで表示する。
class OpponentLocationMarker extends StatelessWidget {
  final Color color;
  const OpponentLocationMarker({super.key, this.color = Colors.red});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Icon(Icons.person_pin_circle, color: color, size: 20),
    );
  }
}
