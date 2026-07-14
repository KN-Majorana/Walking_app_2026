import 'package:flutter/material.dart';

/// 現在地を示す青い丸マーカー
class CurrentLocationMarker extends StatelessWidget {
  const CurrentLocationMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
    );
  }
}
