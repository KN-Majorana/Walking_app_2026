import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'walk_track.dart';

/// 保存済みの散歩記録から1件を選ぶボトムシート。
/// 各記録には削除ボタンがあり、その場で保存済み記録を削除できる。
class TrackPickerSheet extends StatefulWidget {
  final List<WalkTrack> tracks;
  final String? selectedId;

  /// 削除が確定したときに呼ばれる。実際の永続化・状態更新は呼び出し元が行う。
  final void Function(WalkTrack track) onDelete;

  const TrackPickerSheet({
    super.key,
    required this.tracks,
    this.selectedId,
    required this.onDelete,
  });

  static Future<WalkTrack?> show(
    BuildContext context, {
    required List<WalkTrack> tracks,
    String? selectedId,
    required void Function(WalkTrack track) onDelete,
  }) {
    return showModalBottomSheet<WalkTrack>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => TrackPickerSheet(
        tracks: tracks,
        selectedId: selectedId,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<TrackPickerSheet> createState() => _TrackPickerSheetState();
}

class _TrackPickerSheetState extends State<TrackPickerSheet> {
  late List<WalkTrack> _tracks;

  @override
  void initState() {
    super.initState();
    _tracks = List.of(widget.tracks);
  }

  String _label(WalkTrack t) {
    final fmt = DateFormat('M/d HH:mm');
    final start = fmt.format(t.startedAt);
    final pts = t.points.length;
    return '$start　$pts 点';
  }

  Future<void> _confirmDelete(WalkTrack t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('記録を削除'),
        content: Text('${_label(t)} の記録を削除しますか？\nこの操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    widget.onDelete(t);
    if (mounted) {
      setState(() {
        _tracks.removeWhere((x) => x.id == t.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '再生する記録を選ぶ',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          if (_tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('保存された記録がありません',
                  style: TextStyle(color: Colors.black45)),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _tracks.length,
                itemBuilder: (_, i) {
                  final t = _tracks[_tracks.length - 1 - i]; // 新しい順
                  final isSelected = t.id == widget.selectedId;
                  return ListTile(
                    leading: Icon(
                      Icons.history_rounded,
                      color: isSelected
                          ? const Color(0xFF2E7D32)
                          : Colors.black45,
                    ),
                    title: Text(
                      _label(t),
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.check, color: Color(0xFF2E7D32)),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.black45),
                          tooltip: '削除',
                          onPressed: () => _confirmDelete(t),
                        ),
                      ],
                    ),
                    onTap: () => Navigator.pop(context, t),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
