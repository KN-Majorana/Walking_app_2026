import 'dart:io';
import 'package:flutter/material.dart';
import 'color_extraction.dart';
import 'photo_pin.dart';

/// 写真ピンをタップしたときに表示される詳細ボトムシート
class PhotoDetailSheet extends StatelessWidget {
  final PhotoPin pin;
  final VoidCallback? onDelete;

  const PhotoDetailSheet({super.key, required this.pin, this.onDelete});

  /// 表示用のヘルパー（呼び出し側からはこれを使う）
  /// [onDelete] を渡すと削除ボタンが有効になる。
  static void show(
    BuildContext context,
    PhotoPin pin, {
    VoidCallback? onDelete,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PhotoDetailSheet(pin: pin, onDelete: onDelete),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ドラッグハンドル
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // 写真
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(pin.imagePath),
              width: double.infinity,
              height: 280,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 12),

          // 位置情報
          Row(
            children: [
              Icon(Icons.location_on, size: 16, color: primaryColor),
              const SizedBox(width: 4),
              Text(
                '${pin.position.latitude.toStringAsFixed(5)}, '
                '${pin.position.longitude.toStringAsFixed(5)}',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // 撮影日時
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: primaryColor),
              const SizedBox(width: 4),
              Text(
                '${pin.takenAt.year}/${pin.takenAt.month}/${pin.takenAt.day} '
                '${pin.takenAt.hour}:${pin.takenAt.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 抽出された主要色
          if (pin.colorIds.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '検出色',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: pin.colorIds.map((id) {
                final c = colorPalette24[id];
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Color.fromRGBO(c.r, c.g, c.b, 1),
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(colorNames24[id],
                        style: const TextStyle(fontSize: 12)),
                  ],
                );
              }).toList(),
            ),
          ] else ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '色を検出できませんでした',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // 削除ボタン
          if (onDelete != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('ピンを削除'),
                      content: const Text('この写真ピンを削除しますか？\n地図から取り除かれます。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('キャンセル'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          child: const Text('削除'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && context.mounted) {
                    Navigator.pop(context); // ボトムシートを閉じる
                    onDelete!();
                  }
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  foregroundColor: Colors.red,
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('このピンを削除'),
              ),
            ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
