import 'package:flutter/material.dart';

/// ステップC の選択結果
enum PhotoSource { camera, gallery }

/// ステップC：写真の取得元（その場で撮影 / ライブラリ）を選ぶ BottomSheet。
class PhotoSourceSheet {
  static Future<PhotoSource?> show(BuildContext context) {
    return showModalBottomSheet<PhotoSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '写真を選ぶ',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, PhotoSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('その場で撮影する'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, PhotoSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('ライブラリから選ぶ'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
