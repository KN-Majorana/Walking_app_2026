import 'package:flutter/material.dart';

/// 地図上の写真ピン（アセット画像のサムネイル）。
/// 本物の PhotoPinMarker は Image.file を使うが、デモはアセット画像なので
/// Image.asset で描画し、所有者の色で縁取りする。
class DemoPhotoMarker extends StatelessWidget {
  final String asset;
  final Color ringColor;

  const DemoPhotoMarker({
    super.key,
    required this.asset,
    required this.ringColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          width: 50,
          height: 50,
        ),
      ),
    );
  }
}
