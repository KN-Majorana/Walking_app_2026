import 'package:flutter/material.dart';
import 'map_mode.dart';

class ModeSwitcher extends StatelessWidget {
  final MapMode currentMode;
  final ValueChanged<MapMode> onModeChanged;

  const ModeSwitcher({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  static const _items = [
    _ModeItem(
      mode: MapMode.normal,
      label: '通常',
      icon: Icons.map_rounded,
      gradient: [Color(0xFF4FC3F7), Color(0xFF1976D2)],
    ),
    _ModeItem(
      mode: MapMode.fog,
      label: '霧',
      icon: Icons.cloud_rounded,
      gradient: [Color(0xFFB39DDB), Color(0xFF7E57C2)],
    ),
    _ModeItem(
      mode: MapMode.animation,
      label: '再生',
      icon: Icons.play_arrow_rounded,
      gradient: [Color(0xFFFFB74D), Color(0xFFFF7043)],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _items.map((item) {
          final selected = item.mode == currentMode;
          return _ModeButton(
            item: item,
            selected: selected,
            onTap: () => onModeChanged(item.mode),
          );
        }).toList(),
      ),
    );
  }
}

class _ModeItem {
  final MapMode mode;
  final String label;
  final IconData icon;
  final List<Color> gradient;

  const _ModeItem({
    required this.mode,
    required this.label,
    required this.icon,
    required this.gradient,
  });
}

class _ModeButton extends StatelessWidget {
  final _ModeItem item;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: EdgeInsets.symmetric(
          horizontal: selected ? 18 : 14,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  colors: item.gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: item.gradient.last.withValues(alpha: 0.45),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.icon,
              size: 20,
              color: selected ? Colors.white : Colors.grey.shade500,
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: selected
                  ? Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        item.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          letterSpacing: 0.3,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
