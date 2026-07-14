import 'dart:io';
import 'package:flutter/material.dart';
import 'photo_pin.dart';

/// 写真ピンをタップしたときに表示される詳細ボトムシート
class PhotoDetailSheet extends StatelessWidget {
  final PhotoPin pin;

  const PhotoDetailSheet({super.key, required this.pin});

  /// 表示用のヘルパー（呼び出し側からはこれを使う）
  static void show(BuildContext context, PhotoPin pin) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PhotoDetailSheet(pin: pin),
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
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(pin.imagePath),
              width: double.infinity,
              height: 300,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
