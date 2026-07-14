import 'dart:io';

import 'package:flutter/material.dart';

import 'collage_module.dart';
import 'color_module.dart';
import 'photo_pin.dart';
import 'photo_service.dart';

/// 撮影した写真をグリッド表示する一覧画面。
/// 代表色によるフィルタリングと、3種類のコラージュ画面起動が可能。
class PhotoListScreen extends StatefulWidget {
  final List<PhotoPin> photoPins;

  const PhotoListScreen({
    super.key,
    required this.photoPins,
  });

  @override
  State<PhotoListScreen> createState() => _PhotoListScreenState();
}

class _PhotoListScreenState extends State<PhotoListScreen> {
  int? _selectedColorId;

  late List<PhotoPin> _photoPins;

  bool _selectionMode = false;
  final Set<String> _selectedPhotoIds = {};

  @override
  void initState() {
    super.initState();
    _photoPins = List.of(widget.photoPins);
  }

  @override
  void dispose() {
    imageCache.clear();
    imageCache.clearLiveImages();
    super.dispose();
  }

  List<PhotoPin> get _filteredPins {
    if (_selectedColorId == null) return _photoPins;

    return _photoPins
        .where((pin) => pin.colorIds.contains(_selectedColorId))
        .toList();
  }

  int _getRepresentativeColorId(List<PhotoPin> pins) {
    if (_selectedColorId != null) {
      return _selectedColorId!;
    }

    final counts = <int, int>{};

    for (final pin in pins) {
      for (final colorId in pin.colorIds) {
        counts[colorId] = (counts[colorId] ?? 0) + 1;
      }
    }

    if (counts.isEmpty) {
      return 12;
    }

    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.first.key;
  }

  /// 現在の選択写真からコラージュ画面を開く
  /// type: 0=自動配置, 1=自由配置, 2=テンプレ
  void _openCollage(int type) {
    if (_selectionMode) return;

    final filtered = _filteredPins;
    final paths = filtered.map((p) => p.imagePath).toList();

    if (type != 2 && paths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('対象の写真がありません')),
      );
      return;
    }

    Widget page;

    switch (type) {
      case 0:
        page = AutoCollagePage(
          imagePaths: paths,
          colorId: _getRepresentativeColorId(filtered),
        );
        break;

      case 1:
        page = EditableCollagePage(
          imagePaths: const [],
          availablePins: filtered,
          initialColorId: _getRepresentativeColorId(filtered),
        );
        break;

      default:
        page = GridCollagePage(
          availablePins: filtered,
          initialColorId: _getRepresentativeColorId(filtered),
        );
    }

    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  void _toggleSelection(PhotoPin pin) {
    setState(() {
      if (_selectedPhotoIds.contains(pin.id)) {
        _selectedPhotoIds.remove(pin.id);

        if (_selectedPhotoIds.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectedPhotoIds.add(pin.id);
      }
    });
  }

  void _startSelection(PhotoPin pin) {
    setState(() {
      _selectionMode = true;
      _selectedPhotoIds.add(pin.id);
    });
  }

  void _cancelSelection() {
    setState(() {
      _selectionMode = false;
      _selectedPhotoIds.clear();
    });
  }

  Future<void> _deleteSelectedPhotos() async {
    if (_selectedPhotoIds.isEmpty) return;

    final selectedPins = _photoPins
        .where((pin) => _selectedPhotoIds.contains(pin.id))
        .toList();

    if (selectedPins.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('選択した写真を削除しますか？'),
          content: Text(
            '${selectedPins.length}枚の写真と地図上のピンを削除します。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                '削除',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    final deletedIds = selectedPins.map((pin) => pin.id).toList();

    await PhotoService.deletePhotos(selectedPins);

    if (!mounted) return;

    setState(() {
      _photoPins.removeWhere((pin) => deletedIds.contains(pin.id));
      _selectionMode = false;
      _selectedPhotoIds.clear();
    });

    imageCache.clear();
    imageCache.clearLiveImages();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${selectedPins.length}枚削除しました')),
    );

    Navigator.pop(context, deletedIds);
  }

  void _showPhotoPreview(PhotoPin pin) {
    showDialog(
      context: context,
      builder: (_) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(pin.imagePath),
              fit: BoxFit.contain,
              cacheWidth: 1000,
              gaplessPlayback: false,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  height: 260,
                  alignment: Alignment.center,
                  color: Colors.grey.shade200,
                  child: const Icon(
                    Icons.broken_image,
                    size: 48,
                    color: Colors.grey,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildColorFilterBar() {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: const Text('すべて'),
              selected: _selectedColorId == null,
              onSelected: _selectionMode
                  ? null
                  : (_) {
                      imageCache.clear();
                      imageCache.clearLiveImages();

                      setState(() {
                        _selectedColorId = null;
                      });
                    },
            ),
          ),
          for (int i = 0; i < colorPalette24.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _buildColorChip(i),
            ),
        ],
      ),
    );
  }

  Widget _buildColorChip(int colorId) {
    final c = colorPalette24[colorId];
    final color = Color.fromRGBO(c.r, c.g, c.b, 1.0);
    final isSelected = _selectedColorId == colorId;

    final brightness = (c.r * 299 + c.g * 587 + c.b * 114) / 1000;
    final textColor = brightness > 150 ? Colors.black87 : Colors.white;

    return ChoiceChip(
      label: Text(
        colorNames24[colorId],
        style: TextStyle(
          color: isSelected ? textColor : Colors.black87,
          fontSize: 12,
        ),
      ),
      selected: isSelected,
      backgroundColor: color.withValues(alpha: 0.25),
      selectedColor: color,
      side: BorderSide(color: color, width: 1),
      onSelected: _selectionMode
          ? null
          : (sel) {
              imageCache.clear();
              imageCache.clearLiveImages();

              setState(() {
                _selectedColorId = sel ? colorId : null;
              });
            },
    );
  }

  Widget _buildCollageButtons() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _selectionMode ? null : () => _openCollage(0),
                icon: const Icon(Icons.auto_awesome_mosaic, size: 18),
                label: const Text('自動'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _selectionMode ? null : () => _openCollage(1),
                icon: const Icon(Icons.dashboard_customize, size: 18),
                label: const Text('自由'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _selectionMode ? null : () => _openCollage(2),
                icon: const Icon(Icons.grid_view, size: 18),
                label: const Text('テンプレ'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoTile(PhotoPin pin) {
    final selected = _selectedPhotoIds.contains(pin.id);

    return GestureDetector(
      onLongPress: () {
        if (!_selectionMode) {
          _startSelection(pin);
        }
      },
      onTap: () {
        if (_selectionMode) {
          _toggleSelection(pin);
        } else {
          _showPhotoPreview(pin);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(pin.imagePath),
              fit: BoxFit.cover,
              cacheWidth: 300,
              cacheHeight: 300,
              gaplessPlayback: false,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey.shade200,
                  child: const Icon(
                    Icons.broken_image,
                    color: Colors.grey,
                  ),
                );
              },
            ),

            if (_selectionMode)
              Container(
                color: selected
                    ? Colors.black.withValues(alpha: 0.35)
                    : Colors.black.withValues(alpha: 0.08),
              ),

            if (_selectionMode)
              Positioned(
                top: 6,
                right: 6,
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: selected ? Colors.blue : Colors.white,
                  child: Icon(
                    selected ? Icons.check : Icons.circle_outlined,
                    size: 18,
                    color: selected ? Colors.white : Colors.grey,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredPins;

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectionMode) {
          _cancelSelection();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _selectionMode
                ? '${_selectedPhotoIds.length}枚選択中'
                : '撮影した写真',
          ),
          leading: _selectionMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _cancelSelection,
                )
              : null,
          actions: [
            if (_selectionMode)
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed:
                    _selectedPhotoIds.isEmpty ? null : _deleteSelectedPhotos,
              ),
          ],
          backgroundColor: _selectionMode
              ? Colors.red
              : Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            _buildColorFilterBar(),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.camera_alt_outlined,
                            size: 64,
                            color: Colors.black26,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _selectedColorId == null
                                ? 'まだ写真がありません'
                                : 'この色を含む写真はありません',
                            style: const TextStyle(color: Colors.black45),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (_, index) {
                        final pin = filtered[index];
                        return _buildPhotoTile(pin);
                      },
                    ),
            ),
            const Divider(height: 1),
            _buildCollageButtons(),
          ],
        ),
      ),
    );
  }
}