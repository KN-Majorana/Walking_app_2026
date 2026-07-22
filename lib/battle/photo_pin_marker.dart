import 'dart:io';
import 'package:flutter/material.dart';

/// 地図上に表示される写真サムネイルマーカー。
///
/// 対戦モードでは、呼び出し側で `Opacity` により detached ピンを半透明
/// （透過率 45%）にして視覚差を出している（versus_battle_screen 参照）。
/// この Widget 自身は透過制御は行わず、単純なサムネイル描画に徹する。
class PhotoPinMarker extends StatelessWidget {
  final String imagePath;
  const PhotoPinMarker({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    final hasFile = imagePath.isNotEmpty && File(imagePath).existsSync();
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: ClipOval(
        child: hasFile
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
