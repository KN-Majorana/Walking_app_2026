import 'package:flutter/material.dart';

class RecordingControls extends StatelessWidget {
  final bool isRecording;
  final int pointCount;
  final Duration elapsed;
  final double distanceMeters;  // 累計距離(m)
  final double speedKmh;        // 現在速度(km/h)
  final int stepCount;          // 歩数
  final VoidCallback onStart;
  final VoidCallback onStop;

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
  });

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)}km';
    }
    return '${meters.toStringAsFixed(0)}m';
  }

  String _formatSpeed(double kmh) {
    return '${kmh.toStringAsFixed(1)}km/h';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 上段：状態 + 経過時間 + ボタン ──
            Row(
              children: [
                _RecordingDot(isRecording: isRecording),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isRecording ? '散歩中' : 'さあ、出かけよう',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isRecording
                              ? Colors.green.shade700
                              : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _formatDuration(elapsed),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                _WalkActionButton(
                  isRecording: isRecording,
                  onStart: onStart,
                  onStop: onStop,
                ),
              ],
            ),

            // ── 下段：距離・速度・歩数（記録中のみ表示） ──
            if (isRecording) ...[
              const SizedBox(height: 8),
              Container(
                height: 0.5,
                color: Colors.grey.shade200,
              ),
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
                  _StatDivider(),
                  _StatItem(
                    icon: Icons.speed_rounded,
                    value: _formatSpeed(speedKmh),
                    label: 'スピード',
                    color: const Color(0xFF2E7D32),
                  ),
                  _StatDivider(),
                  _StatItem(
                    icon: Icons.directions_walk_rounded,
                    value: '$stepCount歩',
                    label: '歩数',
                    color: const Color(0xFF854F0B),
                  ),
                ],
              ),
            ],
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
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade500,
          ),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 0.5,
      height: 36,
      color: Colors.grey.shade200,
    );
  }
}

/// 散歩開始/終了ボタン
class _WalkActionButton extends StatefulWidget {
  final bool isRecording;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const _WalkActionButton({
    required this.isRecording,
    required this.onStart,
    required this.onStop,
  });

  @override
  State<_WalkActionButton> createState() => _WalkActionButtonState();
}

class _WalkActionButtonState extends State<_WalkActionButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final recording = widget.isRecording;
    final gradient = recording
        ? const [Color(0xFF9E9E9E), Color(0xFF616161)]
        : const [Color(0xFF66BB6A), Color(0xFF2E7D32)];
    final shadowColor =
        recording ? const Color(0xFF616161) : const Color(0xFF2E7D32);
    final icon =
        recording ? Icons.stop_rounded : Icons.directions_walk_rounded;
    final label = recording ? '散歩終了' : '出発！';

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: recording ? widget.onStop : widget.onStart,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: 68,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: shadowColor.withValues(alpha: _pressed ? 0.2 : 0.4),
                blurRadius: _pressed ? 6 : 12,
                offset: Offset(0, _pressed ? 2 : 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 26),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 記録中の点滅ドット
class _RecordingDot extends StatefulWidget {
  final bool isRecording;
  const _RecordingDot({required this.isRecording});

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: widget.isRecording
          ? Tween(begin: 0.3, end: 1.0).animate(_ctrl)
          : const AlwaysStoppedAnimation(1.0),
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.isRecording ? Colors.green : Colors.grey.shade400,
        ),
      ),
    );
  }
}
