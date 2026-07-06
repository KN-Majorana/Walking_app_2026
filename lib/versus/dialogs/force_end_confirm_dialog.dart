import 'package:flutter/material.dart';

/// 相手が「対決を強制終了する」を押したときに表示する確認ダイアログ。
///
/// 「終了する」→ true、「終了しない」→ false を返す。
class ForceEndConfirmDialog {
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('対決を強制終了しますか？'),
        content: const Text('対戦相手が強制終了を提案しています。終了すると多角形の追加は行えなくなります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('終了しない'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('終了する'),
          ),
        ],
      ),
    );
  }
}
