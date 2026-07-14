import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'color_module.dart';

class PhotoColorSelectionResult {
  final Uint8List imageBytes;
  final List<int> colorIds;

  const PhotoColorSelectionResult({
    required this.imageBytes,
    required this.colorIds,
  });
}

class PhotoColorSelectScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final List<int> initialColorIds;
  final int maxSelectableColors;

  const PhotoColorSelectScreen({
    super.key,
    required this.imageBytes,
    required this.initialColorIds,
    this.maxSelectableColors = 3,
  });

  @override
  State<PhotoColorSelectScreen> createState() => _PhotoColorSelectScreenState();
}

class _PhotoColorSelectScreenState extends State<PhotoColorSelectScreen> {
  late final Set<int> selectedColorIds;

  @override
  void initState() {
    super.initState();

    selectedColorIds = widget.initialColorIds
        .where((id) => id >= 0 && id < colorPalette24.length)
        .take(widget.maxSelectableColors)
        .toSet();
  }

  Color _toFlutterColor(ColorRGB color) {
    return Color.fromARGB(255, color.r, color.g, color.b);
  }

  void _toggleColor(int colorId) {
    setState(() {
      if (selectedColorIds.contains(colorId)) {
        selectedColorIds.remove(colorId);
        return;
      }

      if (selectedColorIds.length >= widget.maxSelectableColors) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('選択できる色は最大${widget.maxSelectableColors}色までです'),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      selectedColorIds.add(colorId);
    });
  }

  void _save() {
    if (selectedColorIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('少なくとも1色選択してください'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      PhotoColorSelectionResult(
        imageBytes: widget.imageBytes,
        colorIds: selectedColorIds.toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIds = selectedColorIds.toList();
    final selectedNames = getColorNamesFromIds(selectedIds);

    return Scaffold(
      appBar: AppBar(
        title: const Text('色を選択'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('採用'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              width: double.infinity,
              child: Image.memory(
                widget.imageBytes,
                fit: BoxFit.contain,
              ),
            ),
          ),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              selectedNames.isEmpty
                  ? '色を1〜${widget.maxSelectableColors}色選択してください'
                  : '選択中: ${selectedNames.join(', ')}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${selectedColorIds.length}/${widget.maxSelectableColors}色選択中',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (int i = 0; i < colorPalette24.length; i++)
                  GestureDetector(
                    onTap: () => _toggleColor(i),
                    child: _ColorChipButton(
                      color: _toFlutterColor(colorPalette24[i]),
                      label: colorNames24[i],
                      selected: selectedColorIds.contains(i),
                    ),
                  ),
              ],
            ),
          ),

          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      label: const Text('キャンセル'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check),
                      label: const Text('採用'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorChipButton extends StatelessWidget {
  final Color color;
  final String label;
  final bool selected;

  const _ColorChipButton({
    required this.color,
    required this.label,
    required this.selected,
  });

  bool get _isDark {
    return color.computeLuminance() < 0.45;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 78,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: selected ? Colors.blue.withValues(alpha: 0.10) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? Colors.blueAccent : Colors.grey.shade300,
          width: selected ? 2.5 : 1,
        ),
        boxShadow: [
          if (selected)
            BoxShadow(
              blurRadius: 8,
              offset: const Offset(0, 3),
              color: Colors.blueAccent.withValues(alpha: 0.18),
            ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.black26,
                  ),
                ),
              ),
              if (selected)
                Icon(
                  Icons.check,
                  size: 20,
                  color: _isDark ? Colors.white : Colors.black,
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}