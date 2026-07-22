import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';

import 'collage_gallery_screen.dart';
import 'collage_module.dart';
import 'color_extraction.dart';
import 'models/completed_collage.dart';
import 'photo_pin.dart';
import 'services/completed_collage_storage_service.dart';
import 'stories_collage.dart';

// ═══════════════════════════════════════════════════════════════════
// 「フォト」モードのホーム画面
//   撮影した写真を「色ごと」に並べ、色を選ぶとその色の写真から
//   コラージュ（自動配置＝ストーリー風／自由配置）を作れる。
//   デザインは dart_app1 のコラージュ画面（ダーク基調）に合わせる。
// ═══════════════════════════════════════════════════════════════════

class PhotoModeScreen extends StatelessWidget {
  final List<PhotoPin> photoPins;
  final void Function(Set<String> ids) onDeletePins;

  /// 画面上部に表示するモード切替バー。
  final Widget modeBar;

  const PhotoModeScreen({
    super.key,
    required this.photoPins,
    required this.onDeletePins,
    required this.modeBar,
  });

  /// colorId → その色を含む写真、の一覧（距離制限なし・純粋に色でグループ化）。
  List<({int colorId, List<PhotoPin> pins})> _groupsByColor() {
    final byColor = <int, List<PhotoPin>>{};
    for (final pin in photoPins) {
      for (final id in pin.colorIds) {
        if (id < 0 || id >= colorPalette24.length) continue;
        byColor.putIfAbsent(id, () => []).add(pin);
      }
    }
    final entries = byColor.entries
        .map((e) => (colorId: e.key, pins: e.value))
        .toList()
      ..sort((a, b) => b.pins.length.compareTo(a.pins.length));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupsByColor();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // モード切替バー
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Center(child: modeBar),
            ),
            // ヘッダー
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
              child: Row(
                children: [
                  const Text(
                    'コラージュを作る',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.collections_outlined,
                        color: Colors.white70),
                    tooltip: '完成したコラージュ',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CollageGalleryScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: groups.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.auto_awesome_mosaic_outlined,
                                size: 64, color: Colors.white24),
                            SizedBox(height: 16),
                            Text(
                              'マップモードで散歩しながら写真を撮ると\nここに色ごとの写真が並びます',
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: Colors.white38, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.82,
                      ),
                      itemCount: groups.length,
                      itemBuilder: (_, index) {
                        final g = groups[index];
                        return _ColorGroupCard(
                          colorId: g.colorId,
                          pins: g.pins,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _ColorPhotosScreen(
                                  colorId: g.colorId,
                                  pins: g.pins,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorGroupCard extends StatelessWidget {
  final int colorId;
  final List<PhotoPin> pins;
  final VoidCallback onTap;

  const _ColorGroupCard({
    required this.colorId,
    required this.pins,
    required this.onTap,
  });

  Color get _paletteColor {
    final c = colorPalette24[colorId];
    return Color.fromRGBO(c.r, c.g, c.b, 1);
  }

  String get _colorName => colorNames24[colorId];

  @override
  Widget build(BuildContext context) {
    final thumbPath = pins.isNotEmpty ? pins.first.imagePath : '';
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.grey.shade900),
            if (thumbPath.isNotEmpty)
              Opacity(
                opacity: 0.6,
                child: Image.file(File(thumbPath), fit: BoxFit.cover),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.85),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: _paletteColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _colorName.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${pins.length} 枚',
                      style: TextStyle(
                          color: _paletteColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 選んだ色の写真から、コラージュに使う写真を複数選択する画面
// ═══════════════════════════════════════════════════════════════════

class _ColorPhotosScreen extends StatefulWidget {
  final int colorId;
  final List<PhotoPin> pins;

  const _ColorPhotosScreen({required this.colorId, required this.pins});

  @override
  State<_ColorPhotosScreen> createState() => _ColorPhotosScreenState();
}

class _ColorPhotosScreenState extends State<_ColorPhotosScreen> {
  final Set<String> _selectedIds = <String>{};

  List<PhotoPin> get _selectedPins =>
      widget.pins.where((p) => _selectedIds.contains(p.id)).toList();

  void _toggle(PhotoPin pin) {
    setState(() {
      if (!_selectedIds.add(pin.id)) _selectedIds.remove(pin.id);
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == widget.pins.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(widget.pins.map((p) => p.id));
      }
    });
  }

  Future<void> _chooseMethod() async {
    final selected = _selectedPins;
    if (selected.isEmpty) return;

    final method = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${selected.length}枚で作成',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'auto'),
                icon: const Icon(Icons.grid_view_rounded),
                label: const Text('自動配置'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'free'),
                icon: const Icon(Icons.open_with_rounded),
                label: const Text('自由配置'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || method == null) return;

    if (method == 'auto') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AutoStoriesCollageScreen(
            pins: selected,
            colorId: widget.colorId,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EditableCollagePage(
            imagePaths: selected.map((p) => p.imagePath).toList(),
            availablePins: selected,
            initialColorId: widget.colorId,
            onFinish: (bytes) => _saveFinishedCollage(
              bytes,
              colorId: widget.colorId,
              pins: selected,
              context: context,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final allSelected = widget.pins.isNotEmpty &&
        _selectedIds.length == widget.pins.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${colorNames24[widget.colorId]} · ${_selectedIds.length}枚選択'),
        actions: [
          TextButton(
            onPressed: widget.pins.isEmpty ? null : _selectAll,
            child: Text(allSelected ? '全解除' : 'すべて選択'),
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(10),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 7,
          mainAxisSpacing: 7,
          childAspectRatio: 3 / 4,
        ),
        itemCount: widget.pins.length,
        itemBuilder: (_, index) {
          final pin = widget.pins[index];
          final selected = _selectedIds.contains(pin.id);
          return GestureDetector(
            onTap: () => _toggle(pin),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(File(pin.imagePath), fit: BoxFit.cover),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.blue.withValues(alpha: 0.28)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? Colors.blue : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                if (selected)
                  const Positioned(
                    top: 7,
                    right: 7,
                    child: CircleAvatar(
                      radius: 13,
                      backgroundColor: Colors.blue,
                      child: Icon(Icons.check, color: Colors.white, size: 17),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: FilledButton.icon(
            onPressed: _selectedIds.isEmpty ? null : _chooseMethod,
            icon: const Icon(Icons.navigate_next_rounded),
            label: Text(
              _selectedIds.isEmpty
                  ? '写真を選択してください'
                  : '選択した${_selectedIds.length}枚でコラージュを作る',
            ),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 自動配置（インスタのストーリー風）コラージュ画面
// ═══════════════════════════════════════════════════════════════════

class AutoStoriesCollageScreen extends StatefulWidget {
  final List<PhotoPin> pins;
  final int colorId;

  const AutoStoriesCollageScreen({
    super.key,
    required this.pins,
    required this.colorId,
  });

  @override
  State<AutoStoriesCollageScreen> createState() =>
      _AutoStoriesCollageScreenState();
}

class _AutoStoriesCollageScreenState extends State<AutoStoriesCollageScreen> {
  final GlobalKey _repaintKey = GlobalKey();
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      await _saveFinishedCollage(
        data.buffer.asUint8List(),
        colorId: widget.colorId,
        pins: widget.pins,
        context: context,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('自動配置'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_alt),
            tooltip: '保存',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: RepaintBoundary(
            key: _repaintKey,
            child: StoriesCollage(
              imagePaths: widget.pins.map((p) => p.imagePath).toList(),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_alt),
            label: const Text('保存'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// 共通: 合成画像を「完成コラージュ一覧」とカメラロールへ保存
// ─────────────────────────────────────────

Future<void> _saveFinishedCollage(
  Uint8List pngBytes, {
  required int colorId,
  required List<PhotoPin> pins,
  required BuildContext context,
}) async {
  try {
    final now = DateTime.now();
    final dir = await CompletedCollageStorageService.imagesDir();
    final path = '${dir.path}/collage_${now.microsecondsSinceEpoch}.png';
    await File(path).writeAsBytes(pngBytes, flush: true);

    await CompletedCollageStorageService.save(
      CompletedCollage(
        colorId: colorId,
        pinIds: pins.map((p) => p.id).toList(),
        imagePath: path,
        createdAt: now,
      ),
    );

    final permission = await Permission.photos.request();
    if (permission.isGranted || permission.isLimited) {
      await ImageGallerySaver.saveImage(
        pngBytes,
        quality: 100,
        name: 'collage_${now.millisecondsSinceEpoch}',
        isReturnImagePathOfIOS: false,
      );
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('コラージュ一覧とカメラロールに保存しました')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存に失敗: $e')));
    }
  }
}
