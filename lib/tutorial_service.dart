import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'map_mode.dart';

/// 各モードの初回チュートリアルポップアップを表示するサービス。
///
/// モードごとに「今後は表示しない」を選ぶと、その内容は次回から出さない
/// （SharedPreferences に記録する）。
class TutorialService {
  TutorialService._();

  static String _key(String id) => 'tutorial_hidden_$id';

  /// モード（マップ／フォト／再生）用のチュートリアルを表示する。
  static Future<void> showForMode(BuildContext context, MapMode mode) async {
    final content = switch (mode) {
      MapMode.map => (
          '歩いて、街の霧を晴らそう',
          '散歩の記録を開始して歩くと、通った場所の霧が少しずつ晴れます。対戦で通った場所も通常マップへ反映されます。',
          Icons.map_outlined,
        ),
      MapMode.photo => (
          '街で見つけた色を集めよう',
          '撮影した写真はフォトに保存され、色ごとに並びます。同じ色の写真を選んでコラージュを作れます。',
          Icons.photo_library_outlined,
        ),
      MapMode.animation => (
          '散歩を振り返ろう',
          '記録を選ぶと、その散歩より前に晴れていた場所から始まり、選んだ散歩で霧が晴れていく様子を再生します。「全履歴タイムラプス」で全記録を一気に再生できます。',
          Icons.play_circle_outline,
        ),
    };
    await _show(context, id: mode.name, content: content);
  }

  /// 対戦（オーバーレイ）用のチュートリアルを表示する。
  static Future<void> showForBattle(BuildContext context) async {
    await _show(
      context,
      id: 'battle',
      content: (
        '友だちと街を歩こう',
        '写真の色と撮影地点から陣地を作ります。対戦で通った場所も通常マップの霧晴らしに反映されます。',
        Icons.sports_kabaddi,
      ),
    );
  }

  static Future<void> _show(
    BuildContext context, {
    required String id,
    required (String, String, IconData) content,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_key(id)) == true || !context.mounted) return;

    bool hideNextTime = false;
    final shouldHide = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          icon: Icon(content.$3, size: 42),
          title: Text(content.$1),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(content.$2),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: hideNextTime,
                title: const Text('今後は表示しない'),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (value) =>
                    setState(() => hideNextTime = value ?? false),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, hideNextTime),
              child: const Text('わかった'),
            ),
          ],
        ),
      ),
    );

    if (shouldHide == true) await prefs.setBool(_key(id), true);
  }
}
