import 'package:flutter/material.dart';

/// 再生モード時に過去の自分(ゴースト)の位置を示すマーカー。
class GhostMarker extends StatelessWidget {
  const GhostMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.green,
        border: Border.all(color: Colors.white, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.5),
            blurRadius: 10,
            spreadRadius: 3,
          ),
        ],
      ),
    );
  }
}
