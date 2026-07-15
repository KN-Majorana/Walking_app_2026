import 'package:flutter/material.dart';

/// 散歩記録の開始・停止コントロール
class RecordingControls extends StatelessWidget {
  final bool isRecording;
  final int pointCount;
  final Duration elapsed;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;

  // walk_record 由来の計測値（記録中に表示）
  final double distanceMeters; // 累計距離(m)
  final double speedKmh; // 現在速度(km/h)
  final int stepCount; // 歩数

  /// 開始ボタンのラベル（モードによって変える）
  final String startLabel;

  const RecordingControls({
    super.key,
    required this.isRecording,
    required this.pointCount,
    required this.elapsed,
    required this.onStart,
    required this.onStop,
    this.distanceMeters = 0,
    this.speedKmh = 0,
    this.stepCount = 0,
    this.startLabel = '散歩を記録する',
  });

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)}km';
    }
    return '${meters.toStringAsFixed(0)}m';
  }

  @override
  Widget build(BuildContext context) {
    if (!isRecording) {
      return FilledButton.icon(
        onPressed: onStart,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.blue,
          shape: const StadiumBorder(),
          minimumSize: const Size(0, 48),
        ),
        icon: const Icon(Icons.fiber_manual_record, size: 16),
        label: Text(startLabel),
      );
    }

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 上段：状態 + 経過時間 + 停止ボタン ──
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDuration(elapsed),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$pointCount 点',
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: onStop,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red,
                    shape: const StadiumBorder(),
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text('停止'),
                ),
              ],
            ),

            // ── 下段：距離・速度・歩数 ──
            const SizedBox(height: 8),
            Container(height: 0.5, color: Colors.grey.shade200),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(
                  icon: Icons.straighten_rounded,
                  value: _formatDistance(distanceMeters),
                  label: '距離',
                  color: const Color(0xFF185FA5),
                ),
                _StatItem(
                  icon: Icons.speed_rounded,
                  value: '${speedKmh.toStringAsFixed(1)}km/h',
                  label: 'スピード',
                  color: const Color(0xFF2E7D32),
                ),
                _StatItem(
                  icon: Icons.directions_walk_rounded,
                  value: '$stepCount歩',
                  label: '歩数',
                  color: const Color(0xFF854F0B),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 統計アイテム（アイコン＋値＋ラベル）
class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}
