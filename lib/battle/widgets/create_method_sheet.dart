import 'package:flutter/material.dart';

/// ステップA の選択結果
enum PolygonCreateMethod { createNew, addExisting }

/// ステップA：作成方法（新規 / 既存追加）を選ぶ BottomSheet。
class CreateMethodSheet {
  /// [hasExisting] が false の場合、「既存に追加」を選択不可にする。
  static Future<PolygonCreateMethod?> show(
    BuildContext context, {
    required bool hasExisting,
  }) {
    return showModalBottomSheet<PolygonCreateMethod>(
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
                        '多角形を作る',
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
                  onPressed: () =>
                      Navigator.pop(ctx, PolygonCreateMethod.createNew),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('新しい多角形を作る'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: hasExisting
                      ? () => Navigator.pop(
                            ctx,
                            PolygonCreateMethod.addExisting,
                          )
                      : null,
                  icon: const Icon(Icons.add_to_photos_outlined),
                  label: const Text('既存の多角形に追加する'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                if (!hasExisting) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'まだ多角形がありません。まず新しい多角形を作ってください',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
