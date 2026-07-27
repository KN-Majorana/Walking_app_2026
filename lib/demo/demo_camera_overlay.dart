import 'package:flutter/material.dart';

/// 「カメラを起動して撮影した」演出のフルスクリーンオーバーレイ。
///
/// 実カメラは使わず、assets/demo_photos の写真を表示する。
/// プレイヤーの色でフレームを付け、どちらが撮影したかを示す。
class DemoCameraOverlay extends StatelessWidget {
  final String asset;
  final Color color;
  final String title;

  const DemoCameraOverlay({
    super.key,
    required this.asset,
    required this.color,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.82),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt, color: color, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'カメラ起動 — $title',
                    style: TextStyle(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: color, width: 5),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.6),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(asset, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'この地点に写真ピンを刺しました',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
