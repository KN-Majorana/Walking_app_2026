import 'package:flutter/material.dart';
import 'map_mode.dart';

/// 地図モードを切り替えるタブUI
class ModeSwitcher extends StatelessWidget {
  final MapMode currentMode;
  final void Function(MapMode) onModeChanged;

  const ModeSwitcher({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Tab(
              label: 'フォト',
              icon: Icons.photo_library_outlined,
              isSelected: currentMode == MapMode.photo,
              onTap: () => onModeChanged(MapMode.photo),
              activeColor: Colors.indigo,
            ),
            _Tab(
              label: 'マップ',
              icon: Icons.map_outlined,
              isSelected: currentMode == MapMode.map,
              onTap: () => onModeChanged(MapMode.map),
              activeColor: const Color(0xFF00796B),
            ),
            // 対戦はモードタブから外し、マップモードの左端スワイプで
            // 全画面オーバーレイとして呼び出す方式に変更した。
            _Tab(
              label: '再生',
              icon: Icons.play_circle_outline,
              isSelected: currentMode == MapMode.animation,
              onTap: () => onModeChanged(MapMode.animation),
              activeColor: const Color(0xFF2E7D32),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final Color activeColor;

  const _Tab({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.activeColor = Colors.blue,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.black54,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
