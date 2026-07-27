import 'dart:io';

import 'package:flutter/material.dart';

import 'color_extraction.dart';
import 'models/completed_collage.dart';
import 'services/completed_collage_storage_service.dart';

/// これまでに完成させたコラージュの一覧画面
class CollageGalleryScreen extends StatefulWidget {
  const CollageGalleryScreen({super.key});

  @override
  State<CollageGalleryScreen> createState() => _CollageGalleryScreenState();
}

class _CollageGalleryScreenState extends State<CollageGalleryScreen> {
  List<CompletedCollage> _collages = [];
  bool _loading = true;

  /// 選択中のコラージュID
  final Set<String> _selected = {};

  /// 選択モード中かどうか
  bool get _isSelecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await CompletedCollageStorageService.loadAll();
    // 新しいものを先頭に
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted) return;
    setState(() {
      _collages = list;
      _loading = false;
    });
  }

  /// 選択をすべてクリア
  void _clearSelection() => setState(() => _selected.clear());

  /// タップ: 選択中なら選択トグル、そうでなければ拡大表示
  void _handleTap(CompletedCollage collage) {
    if (_isSelecting) {
      setState(() {
        if (_selected.contains(collage.id)) {
          _selected.remove(collage.id);
        } else {
          _selected.add(collage.id);
        }
      });
    } else {
      _openViewer(collage);
    }
  }

  /// 長押しで選択モードに入る
  void _handleLongPress(CompletedCollage collage) {
    setState(() => _selected.add(collage.id));
  }

  /// 選択モードでの削除を実行
  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('コラージュを削除'),
        content: Text('選択した $count 件の完成コラージュを削除しますか？\nこの操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await CompletedCollageStorageService.deleteMany(Set.from(_selected));
    _selected.clear();
    await _load();
  }

  String _colorNameFor(CompletedCollage c) =>
      (c.colorId >= 0 && c.colorId < colorNames24.length)
      ? colorNames24[c.colorId]
      : '?';

  Color _colorFor(CompletedCollage c) {
    if (c.colorId < 0 || c.colorId >= colorPalette24.length) {
      return Colors.white38;
    }
    final rgb = colorPalette24[c.colorId];
    return Color.fromRGBO(rgb.r, rgb.g, rgb.b, 1);
  }

  Future<void> _openViewer(CompletedCollage collage) async {
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _CollageViewerScreen(
          collage: collage,
          colorName: _colorNameFor(collage),
          paletteColor: _colorFor(collage),
        ),
      ),
    );
    // ビューア側で削除された場合は一覧を更新する
    if (deleted == true) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: _isSelecting
            ? Text('${_selected.length} 件選択中')
            : const Text(
                '完成したコラージュ',
                style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold, fontSize: 15),
              ),
        backgroundColor: _isSelecting ? Colors.red.shade700 : Colors.black,
        foregroundColor: Colors.white,
        leading: _isSelecting
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              )
            : null,
        actions: _isSelecting
            ? [
                // 全選択トグル
                IconButton(
                  icon: Icon(
                    _selected.length == _collages.length
                        ? Icons.deselect
                        : Icons.select_all,
                  ),
                  tooltip: _selected.length == _collages.length ? '全解除' : '全選択',
                  onPressed: () {
                    setState(() {
                      if (_selected.length == _collages.length) {
                        _selected.clear();
                      } else {
                        _selected.addAll(_collages.map((c) => c.id));
                      }
                    });
                  },
                ),
              ]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white38))
          : _collages.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.collections_outlined, size: 64, color: Colors.white24),
                  SizedBox(height: 16),
                  Text(
                    'まだ完成したコラージュがありません',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 9 / 16,
              ),
              itemCount: _collages.length,
              itemBuilder: (_, index) {
                final collage = _collages[index];
                final paletteColor = _colorFor(collage);
                final isSelected = _selected.contains(collage.id);
                return GestureDetector(
                  onTap: () => _handleTap(collage),
                  onLongPress: () => _handleLongPress(collage),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(collage.imagePath), fit: BoxFit.cover),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.75),
                                ],
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8, height: 8,
                                  decoration: BoxDecoration(
                                    color: paletteColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _colorNameFor(collage).toUpperCase(),
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
                          ),
                        ),

                        // 選択中のオーバーレイ
                        if (_isSelecting)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            color: isSelected
                                ? Colors.red.withValues(alpha: 0.35)
                                : Colors.black.withValues(alpha: 0.15),
                          ),

                        // チェックマーク（選択モード時）
                        if (_isSelecting)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: AnimatedScale(
                              scale: isSelected ? 1.0 : 0.7,
                              duration: const Duration(milliseconds: 150),
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected ? Colors.red : Colors.white60,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),

      // 削除ボタン（選択モード時のみ表示）
      bottomNavigationBar: _isSelecting
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: FilledButton.icon(
                  onPressed: _deleteSelected,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: Text('${_selected.length} 件を削除'),
                ),
              ),
            )
          : null,
    );
  }
}

/// コラージュの拡大表示画面
class _CollageViewerScreen extends StatelessWidget {
  final CompletedCollage collage;
  final String colorName;
  final Color paletteColor;

  const _CollageViewerScreen({
    required this.collage,
    required this.colorName,
    required this.paletteColor,
  });

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('コラージュを削除'),
        content: const Text('このコラージュを削除しますか？\nこの操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await CompletedCollageStorageService.delete(collage.id);
    // true を返して呼び出し元（一覧画面）に削除を伝え、一覧を更新させる
    if (context.mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final date = collage.createdAt;
    final dateLabel =
        '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(color: paletteColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              colorName.toUpperCase(),
              style: const TextStyle(fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '削除',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(collage.imagePath), fit: BoxFit.contain),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                '$dateLabel に完成',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
