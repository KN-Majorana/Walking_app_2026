import 'package:flutter/material.dart';

import '../../models/battle.dart';

/// 対決の申込を受信したときに、アプリ全体に被せるモーダル。
class ChallengeIncomingDialog extends StatelessWidget {
  final Battle battle;

  /// 「対決する」or「対決しない」の結果（accept=true / decline=false）を返す。
  static Future<bool?> show(BuildContext context, Battle battle) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChallengeIncomingDialog(battle: battle),
    );
  }

  const ChallengeIncomingDialog({super.key, required this.battle});

  @override
  Widget build(BuildContext context) {
    final name = battle.challengerName ?? 'プレイヤー';
    return AlertDialog(
      title: const Text('対決の申込'),
      content: Text('$name から対決が申し込まれています。対決しますか？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('対決しない'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('対決する'),
        ),
      ],
    );
  }
}
