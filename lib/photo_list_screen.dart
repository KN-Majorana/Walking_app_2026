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

  /// 「この場所に移動」で呼ばれるコールバック。
  /// null のときはボタンを出さない（地図の無いフォトモードから開いた場合）。
  /// 呼び出し側で一覧を閉じ、地図をその座標へ動かす。
  final void Function(PhotoPin pin)? onMoveToPin;

  const PhotoListScreen({
    super.key,
    required this.photoPins,
    this.onDeletePins,
    this.onMoveToPin,
  });

  @override
  State<PhotoListScreen> createState() => _PhotoListScreenState();
}

class _PhotoListScreenState extends State<PhotoListScreen> {
  /// 表示用の作業コピー。
  /// 呼び出し元から渡されるリストは合成済み（散歩＋対戦履歴）で
  /// 親の State と同一インスタンスとは限らないため、削除結果を
  /// 即座に反映できるよう自前のコピーを保持する。
  late List<PhotoPin> _pins = List.of(widget.photoPins);

  @override
  void didUpdateWidget(covariant PhotoListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.photoPins, widget.photoPins)) {
      _pins = List.of(widget.photoPins);
    }
  }

  /// 選択中のピンID
  final Set<String> _selected = {};

  /// 選択モード中かどうか。
  /// 以前は「1枚以上選択中」で判定していたため、全解除すると勝手にモードが
  /// 抜けてしまい、長押し以外に入口も無かった。明示的なフラグで管理する。
  bool _selectMode = false;
  bool get _isSelecting => _selectMode;

  /// 選択モードに入る（AppBar の「選択」ボタン／長押しから）
  void _enterSelection([String? initialId]) {
    setState(() {
      _selectMode = true;
      if (initialId != null) _selected.add(initialId);
    });
  }

  /// 選択モードを抜ける
  void _clearSelection() => setState(() {
        _selectMode = false;
        _selected.clear();
      });

  /// 確認ダイアログを出して削除する。[ids] が空なら何もしない。
  Future<void> _confirmAndDelete(Set<String> ids) async {
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('写真を削除'),
        content: Text('${ids.length} 枚の写真を削除しますか？\nこの操作は取り消せません。'),
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
    widget.onDeletePins?.call(ids);
    setState(() {
      _pins.removeWhere((p) => ids.contains(p.id));
      _selected.removeAll(ids);
      if (_selected.isEmpty) _selectMode = false;
    });
  }

  /// 選択モードでの削除を実行
  Future<void> _deleteSelected() => _confirmAndDelete(Set.of(_selected));

  /// 拡大表示から1枚だけ削除する
  Future<void> _deleteSingle(PhotoPin pin) => _confirmAndDelete({pin.id});

  /// 写真の拡大表示。ここからも削除できる。
  void _showPhoto(PhotoPin pin) {
    showDialog<void>(
      context: context,
      builder: (dctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: Image.file(File(pin.imagePath)),
              ),
            ),
            // ボタンが3つ並ぶと幅の狭い端末で溢れるため、はみ出す場合は
            // 折り返す（Wrap）。
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(dctx);
                      _deleteSingle(pin);
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('削除'),
                  ),
                  // 地図のある画面から開いたときだけ表示する
                  if (widget.onMoveToPin != null)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(dctx); // 拡大表示を閉じる
                        widget.onMoveToPin!(pin); // 一覧を閉じて地図を動かす
                      },
                      icon: const Icon(Icons.my_location),
                      label: const Text('この場所に移動'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(dctx),
                    child: const Text('閉じる'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 表示用のリスト（作業コピー）
    final pins = _pins;

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
            : [
                // 長押しに気づかなくても削除できるよう、明示的な入口を置く。
                if (pins.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _enterSelection(),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('選択'),
                  ),
              ],
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
                      _showPhoto(pin);
                    }
                  },
                  // 長押しでも選択モードに入る
                  onLongPress: () => _enterSelection(pin.id),
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
