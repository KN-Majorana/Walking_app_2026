import 'package:flutter/material.dart';

/// 散歩記録の開始・停止コントロール
class RecordingControls extends StatelessWidget {
  final bool isRecording;
  final int pointCount;
  final Duration elapsed;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;

  const RecordingControls({
    super.key,
    required this.isRecording,
    required this.pointCount,
    required this.elapsed,
    required this.onStart,
    required this.onStop,
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
        label: const Text('散歩を記録する'),
      );
    }

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
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
      ),
    );
  }
}
