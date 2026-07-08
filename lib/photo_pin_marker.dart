import 'dart:io';
import 'package:flutter/material.dart';

/// 地図上に表示される写真サムネイルマーカー
class PhotoPinMarker extends StatelessWidget {
  final String imagePath;
  const PhotoPinMarker({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: ClipOval(
        child: imagePath.isNotEmpty && File(imagePath).existsSync()
            ? Image.file(
                File(imagePath),
                fit: BoxFit.cover,
                width: 52,
                height: 52,
              )
            : Container(
                width: 52,
                height: 52,
                color: Colors.grey.shade300,
                child: const Icon(Icons.image_not_supported_outlined,
                    size: 24, color: Colors.grey),
              ),
      ),
    );
  }
}
