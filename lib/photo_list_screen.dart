import 'dart:io';
import 'package:flutter/material.dart';
import 'color_extraction.dart';
import 'photo_pin.dart';

/// 撮影した写真をグリッド表示する一覧画面
/// 長押しで選択モードに入り、複数選択して削除できる。
class PhotoListScreen extends StatefulWidget {
  final List<PhotoPin> photoPins;

  /// 削除が確定したときに呼ばれるコールバック。
  /// 引数は削除対象の pin.id のセット。
  final void Function(Set<String> ids)? onDeletePins;

  const PhotoListScreen({
    super.key,
    required this.photoPins,
    this.onDeletePins,
  });

  @override
  State<PhotoListScreen> createState() => _PhotoListScreenState();
}

class _PhotoListScreenState extends State<PhotoListScreen> {
  /// 選択中のピンID
  final Set<String> _selected = {};

  /// 選択モード中かどうか
  bool get _isSelecting => _selected.isNotEmpty;

  /// 選択をすべてクリア
  void _clearSelection() => setState(() => _selected.clear());

  /// 選択モードでの削除を実行
  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('写真を削除'),
        content: Text('選択した $count 枚の写真ピンを削除しますか？'),
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
    if (confirmed == true && mounted) {
      widget.onDeletePins?.call(Set.from(_selected));
      _clearSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 表示用のリスト（削除後は親から再ビルドされるが、選択中は手元のリストを使う）
    final pins = widget.photoPins;

    return Scaffold(
      appBar: AppBar(
        title: _isSelecting
            ? Text('${_selected.length} 枚選択中')
            : const Text('撮影した写真'),
        backgroundColor: _isSelecting
            ? Colors.red.shade700
            : Theme.of(context).colorScheme.primary,
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
                    _selected.length == pins.length
                        ? Icons.deselect
                        : Icons.select_all,
                  ),
                  tooltip: _selected.length == pins.length ? '全解除' : '全選択',
                  onPressed: () {
                    setState(() {
                      if (_selected.length == pins.length) {
                        _selected.clear();
                      } else {
                        _selected.addAll(pins.map((p) => p.id));
                      }
                    });
                  },
                ),
              ]
            : null,
      ),
      body: pins.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt_outlined, size: 64, color: Colors.black26),
                  SizedBox(height: 16),
                  Text('まだ写真がありません', style: TextStyle(color: Colors.black45)),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: pins.length,
              itemBuilder: (_, index) {
                final pin = pins[index];
                final isSelected = _selected.contains(pin.id);

                return GestureDetector(
                  // 通常タップ：選択中なら選択トグル、そうでなければ拡大表示
                  onTap: () {
                    if (_isSelecting) {
                      setState(() {
                        if (isSelected) {
                          _selected.remove(pin.id);
                        } else {
                          _selected.add(pin.id);
                        }
                      });
                    } else {
                      showDialog(
                        context: context,
                        builder: (_) => Dialog(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(File(pin.imagePath)),
                          ),
                        ),
                      );
                    }
                  },
                  // 長押しで選択モードに入る
                  onLongPress: () {
                    setState(() => _selected.add(pin.id));
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // サムネイル
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(pin.imagePath), fit: BoxFit.cover),
                      ),

                      // 選択中のオーバーレイ
                      if (_isSelecting)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            color: isSelected
                                ? Colors.red.withValues(alpha: 0.35)
                                : Colors.black.withValues(alpha: 0.15),
                          ),
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

                      // 色ドット（右下）
                      if (pin.colorIds.isNotEmpty)
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: pin.colorIds.map((id) {
                              final c = colorPalette24[id];
                              return Container(
                                width: 10,
                                height: 10,
                                margin: const EdgeInsets.only(left: 2),
                                decoration: BoxDecoration(
                                  color: Color.fromRGBO(c.r, c.g, c.b, 1),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 1),
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                      // 色未検出マーク
                      if (pin.colorIds.isEmpty)
                        const Positioned(
                          bottom: 4,
                          right: 4,
                          child: Icon(Icons.not_interested, size: 14, color: Colors.white70),
                        ),
                    ],
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
                  label: Text('${_selected.length} 枚を削除'),
                ),
              ),
            )
          : null,
    );
  }
}
