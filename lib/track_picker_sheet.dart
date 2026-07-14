import 'package:flutter/material.dart';

import 'walk_track.dart';

/// 保存済み軌跡の一覧から1件選ぶためのボトムシート。
///
/// 選ばれた軌跡が返り値として返る。何も選ばずに閉じた場合は null。
class TrackPickerSheet {
  TrackPickerSheet._();

  static Future<WalkTrack?> show(
    BuildContext context, {
    required List<WalkTrack> tracks,
    String? selectedId,
  }) {
    return showModalBottomSheet<WalkTrack>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _TrackPickerSheetBody(tracks: tracks, selectedId: selectedId),
    );
  }
}

class _TrackPickerSheetBody extends StatelessWidget {
  final List<WalkTrack> tracks;
  final String? selectedId;

  const _TrackPickerSheetBody({required this.tracks, required this.selectedId});

  /// 軌跡の所要時間。endedAtがあればそれを使い、無ければ点列のタイムスタンプから推定。
  Duration _durationOf(WalkTrack t) {
    if (t.endedAt != null) {
      return t.endedAt!.difference(t.startedAt);
    }
    if (t.points.length >= 2) {
      return t.points.last.timestamp.difference(t.points.first.timestamp);
    }
    return Duration.zero;
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String _formatDate(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}/${two(dt.month)}/${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    // 新しい順に並べる
    final sorted = [...tracks]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 16,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // ハンドル
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // タイトル
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    const Icon(Icons.history_rounded, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 8),
                    const Text(
                      '散歩の記録',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${sorted.length}件',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // 一覧
              Expanded(
                child: sorted.isEmpty
                    ? Center(
                        child: Text(
                          'まだ記録がありません',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: sorted.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 20, endIndent: 20),
                        itemBuilder: (context, i) {
                          final t = sorted[i];
                          final selected = t.id == selectedId;
                          return _TrackRow(
                            track: t,
                            duration: _durationOf(t),
                            dateText: _formatDate(t.startedAt),
                            durationText: _formatDuration(_durationOf(t)),
                            selected: selected,
                            onTap: () => Navigator.of(context).pop(t),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TrackRow extends StatelessWidget {
  final WalkTrack track;
  final Duration duration;
  final String dateText;
  final String durationText;
  final bool selected;
  final VoidCallback onTap;

  const _TrackRow({
    required this.track,
    required this.duration,
    required this.dateText,
    required this.durationText,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected
            ? const Color(0xFF66BB6A).withValues(alpha: 0.1)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            // 左のアイコン
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF66BB6A), Color(0xFF2E7D32)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.directions_walk_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            // テキスト
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateText,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        durationText,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.place_outlined,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${track.points.length}点',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                Icons.play_circle_filled_rounded,
                color: Color(0xFF2E7D32),
                size: 28,
              )
            else
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
