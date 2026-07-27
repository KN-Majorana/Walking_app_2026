import 'package:flutter/material.dart';

import 'demo_config.dart';
import 'demo_battle_screen.dart';

/// 対戦デモのロビー画面。
///
/// 本物のロビー（versus_lobby_screen）は Firebase のフレンド一覧を購読して
/// 「申込 → 承認」で対戦成立するが、デモでは 1 人の対戦相手（赤）を固定表示し、
/// 「対戦相手にする」を押すとその場で対戦（自動再生）を開始する。
class DemoLobbyScreen extends StatelessWidget {
  const DemoLobbyScreen({super.key});

  void _startBattle(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DemoBattleScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('対決を始める（デモ）'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 自分のカード（青 / challenger）
            Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _ColorDot(color: DemoConfig.challengerColor),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('あなた（青 / challenger）',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('あなたのコード: DEMO-0001'),
                    const SizedBox(height: 12),
                    Row(
                      children: const [
                        Text('制限時間'),
                        SizedBox(width: 12),
                        Chip(label: Text('15 分')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('対戦相手を選んで対戦を申し込む',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 4),
            // 対戦相手（赤 / opponent）
            ListTile(
              leading: CircleAvatar(
                backgroundColor: DemoConfig.opponentColor,
                child: const Text('赤',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              title: const Text('あいて（赤 / opponent）'),
              subtitle: const Text('コード: DEMO-0002'),
              trailing: FilledButton(
                onPressed: () => _startBattle(context),
                child: const Text('対戦相手にする'),
              ),
            ),
            const Divider(height: 1),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'これは integration_Ver1 の対戦機能を 1 台の端末で説明するデモです。'
                '「対戦相手にする」を押すと、青(あなた)と赤(あいて)が自動で移動し、'
                '各地点でカメラを起動して写真ピンを刺していきます。',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  const _ColorDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black26),
      ),
    );
  }
}
