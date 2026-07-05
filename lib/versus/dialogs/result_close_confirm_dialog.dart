import 'package:flutter/material.dart';

/// 相手がリザルト画面を終了しようとしたときに表示する確認ダイアログ。
///
/// 「終了する」→ true、「終了しない」→ false を返す。
/// true を返した場合、対戦データは完全消去されロビーへ戻る。
class ResultCloseConfirmDialog {
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('リザルト画面を終了しますか？'),
        content: const Text(
            '対戦相手がリザルト画面の終了を提案しています。終了すると対戦データは削除されロビーに戻ります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('終了しない'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('終了する'),
          ),
        ],
      ),
    );
  }
}
