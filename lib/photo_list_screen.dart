import 'dart:io';
import 'package:flutter/material.dart';
import 'color_extraction.dart';
import 'photo_pin.dart';

/// 対戦モード中の写真一覧画面。
///
/// スコープは「現在の battle 内で撮った写真」のみ。
/// 過去 battle の写真は cleared 時に全削除されるため、アプリ内には存在しない。
///
/// 対戦モードでは個別の写真削除は行えない（写真データが battle 中は
/// 保持される仕様）。したがって削除 UI は撤去し、閲覧専用とする。
class PhotoListScreen extends StatelessWidget {
  final List<PhotoPin> photoPins;

  const PhotoListScreen({super.key, required this.photoPins});

  @override
  Widget build(BuildContext context) {
    final pins = photoPins;
    return Scaffold(
      appBar: AppBar(
        title: const Text('対戦中の写真'),
      ),
      body: pins.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt_outlined, size: 64, color: Colors.black26),
                  SizedBox(height: 16),
                  Text('まだ写真がありません', style: TextStyle(color: Colors.black45)),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: pins.length,
              itemBuilder: (_, index) {
                final pin = pins[index];
                final canShow =
                    pin.hasImageOnDevice && pin.imagePath.isNotEmpty;
                return GestureDetector(
                  onTap: () {
                    if (!canShow) return;
                    showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(File(pin.imagePath)),
                        ),
                      ),
                    );
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: canShow
                            ? Image.file(File(pin.imagePath), fit: BoxFit.cover)
                            : Container(
                                color: Colors.grey.shade300,
                                child: const Icon(
                                  Icons.image_not_supported_outlined,
                                  color: Colors.grey,
                                ),
                              ),
                      ),
                      if (pin.isDetached)
                        Container(
                          color: Colors.black.withValues(alpha: 0.35),
                          alignment: Alignment.center,
                          child: const Text(
                            '切り離し済み',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (pin.colorIds.isNotEmpty)
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: pin.colorIds.map((id) {
                              final c = colorPalette24[id];
                              return Container(
                                width: 10,
                                height: 10,
                                margin: const EdgeInsets.only(left: 2),
                                decoration: BoxDecoration(
                                  color: Color.fromRGBO(c.r, c.g, c.b, 1),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 1),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
