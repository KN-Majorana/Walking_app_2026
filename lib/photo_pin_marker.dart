import 'dart:io';
import 'package:flutter/material.dart';

/// 地図上に表示される写真サムネイルマーカー
class PhotoPinMarker extends StatelessWidget {
  final String imagePath;

  /// サムネイルの直径。地図の縮尺に応じて呼び出し側が変える。
  final double size;

  const PhotoPinMarker({
    super.key,
    required this.imagePath,
    this.size = 52,
  });

  @override
  Widget build(BuildContext context) {
    // 枠線とアイコンも大きさに合わせて調整する（小さいときに枠が太く見えない）。
    final borderWidth = (size / 26).clamp(1.0, 2.0);
    final placeholderIcon = (size * 0.46).clamp(12.0, 24.0);

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: borderWidth),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: ClipOval(
        child: imagePath.isNotEmpty && File(imagePath).existsSync()
            ? Image.file(
                File(imagePath),
                fit: BoxFit.cover,
                width: size,
                height: size,
              )
            : Container(
                width: size,
                height: size,
                color: Colors.grey.shade300,
                child: Icon(Icons.image_not_supported_outlined,
                    size: placeholderIcon, color: Colors.grey),
              ),
      ),
    );
  }
}
