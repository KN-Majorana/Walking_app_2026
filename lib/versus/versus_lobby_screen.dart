import 'dart:async';

import 'package:flutter/material.dart';

import '../models/battle.dart';
import '../models/friend_profile.dart';
import '../services/battle_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_sync_service.dart';
import 'dialogs/challenge_incoming_dialog.dart';
import 'friends_screen.dart';
import 'versus_battle_screen.dart';
import 'versus_result_screen.dart';

/// idle 状態のロビー画面。
///
///   - 自分の userId（フレンドコード）表示
///   - フレンド追加ボタン / フレンド一覧
///   - 各行「対戦相手にする」ボタン
///   - 時間制限プルダウン（15 分 / 30 分 / 1 時間 / 2 時間）
///
/// フレンドを選ぶと Firestore に battle(pending) を書き込み、B の応答待ちに入る。
///
/// このスクリーンは opponentUid=me の pending battle も購読しており、
/// 対決の申込を受信するとポップアップを表示する。
class VersusLobbyScreen extends StatefulWidget {
  const VersusLobbyScreen({super.key});

  @override
  State<VersusLobbyScreen> createState() => _VersusLobbyScreenState();
}

class _VersusLobbyScreenState extends State<VersusLobbyScreen> {
  FriendProfile? _me;
  bool _loading = true;
  int _timeLimitSec = 3600;

  StreamSubscription<List<Battle>>? _incomingSub;
  bool _handlingIncoming = false;

  /// A（自分）が発した pending 申込を待つ間のダイアログ制御。
  Battle? _pendingSent;
  StreamSubscription<Battle?>? _pendingSub;

  static const _timeChoices = <int, String>{
    900: '15 分',
    1800: '30 分',
    3600: '1 時間',
    7200: '2 時間',
  };

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _pendingSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final uid = await FirebaseAuthService.ensureSignedIn();
      final existing = await FirestoreSyncService.getMyProfile();
      final name = existing?.displayName ??
          'プレイヤー${uid.substring(uid.length - 4).toUpperCase()}';
      final me = await FirestoreSyncService.ensureUserDoc(name);
      if (!mounted) return;
      setState(() {
        _me = me;
        _loading = false;
      });
      _subscribeIncoming();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('初期化に失敗: $e')),
      );
    }
  }

  void _subscribeIncoming() {
    final me = _me;
    if (me == null) return;
    _incomingSub =
        BattleService.watchIncomingChallenges(me.uid).listen((list) async {
      if (list.isEmpty || _handlingIncoming) return;
      // 自分が発した pending は着信ではないので、challengerUid==me は除外
      final incoming =
          list.firstWhere((b) => b.challengerUid != me.uid, orElse: () => list.first);
      if (incoming.challengerUid == me.uid) return;

      _handlingIncoming = true;
      try {
        final ok = await ChallengeIncomingDialog.show(context, incoming);
        if (!mounted) return;
        if (ok == true) {
          try {
            final active = await BattleService.acceptChallenge(incoming.id);
            if (!mounted) return;
            _navigateToBattle(active);
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$e')),
            );
          }
        } else if (ok == false) {
          await BattleService.declineChallenge(incoming.id);
        }
      } finally {
        _handlingIncoming = false;
      }
    });
  }

  Future<void> _requestChallenge(FriendProfile friend) async {
    final me = _me;
    if (me == null) return;
    try {
      final battle = await BattleService.requestChallenge(
        challengerUid: me.uid,
        challengerName: me.displayName,
        opponentUid: friend.uid,
        opponentName: friend.displayName,
        timeLimitSec: _timeLimitSec,
      );
      if (!mounted) return;
      _showWaitingDialog(battle);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  void _showWaitingDialog(Battle battle) {
    setState(() => _pendingSent = battle);
    _pendingSub?.cancel();
    _pendingSub = BattleService.watchBattle(battle.id).listen((b) async {
      if (b == null) return;
      switch (b.status) {
        case BattleStatus.active:
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true).pop(); // 待機ダイアログを閉じる
          _navigateToBattle(b);
          break;
        case BattleStatus.declined:
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('相手に断られました')),
          );
          setState(() => _pendingSent = null);
          break;
        case BattleStatus.expired:
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('応答期限が切れました')),
          );
          setState(() => _pendingSent = null);
          break;
        default:
          break;
      }
    });

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('応答待ち'),
        content: Row(
          children: const [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('相手の応答を待っています…')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              await BattleService.cancelChallenge(battle.id);
              _pendingSub?.cancel();
              if (mounted) setState(() => _pendingSent = null);
            },
            child: const Text('キャンセル'),
          ),
        ],
      ),
    ).then((_) {
      _pendingSub?.cancel();
    });
  }

  void _navigateToBattle(Battle battle) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => VersusBattleScreen(battleId: battle.id)),
    );
  }

  void _navigateToResult(Battle battle) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => VersusResultScreen(battleId: battle.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final me = _me;
    if (me == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('対決を始める')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('接続できませんでした。ネットワークを確認してください。'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('対決を始める'),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_outlined),
            tooltip: 'フレンド',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => FriendsScreen(myProfile: me)),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(me.displayName,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('あなたのコード: ${me.code ?? '----'}'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('制限時間'),
                        const SizedBox(width: 12),
                        DropdownButton<int>(
                          value: _timeLimitSec,
                          items: _timeChoices.entries
                              .map((e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.value),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _timeLimitSec = v);
                            }
                          },
                        ),
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
                child: Text('フレンドを選んで対戦を申し込む',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<FriendProfile>>(
                stream: FirestoreSyncService.watchFriends(),
                builder: (ctx, snap) {
                  final list = snap.data ?? const <FriendProfile>[];
                  if (list.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('まだフレンドがいません',
                              style: TextStyle(color: Colors.black45)),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            icon: const Icon(Icons.person_add_alt),
                            label: const Text('フレンドを追加'),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        FriendsScreen(myProfile: me)),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final f = list[i];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(f.displayName.characters.first),
                        ),
                        title: Text(f.displayName),
                        subtitle: Text('コード: ${f.code ?? '----'}'),
                        trailing: FilledButton(
                          onPressed: () => _requestChallenge(f),
                          child: const Text('対戦相手にする'),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
