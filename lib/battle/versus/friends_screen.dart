import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/friend_profile.dart';
import '../services/firestore_sync_service.dart';

/// フレンドの追加・一覧表示・削除画面。
///
/// versus_lobby_screen から呼ばれ、対戦相手の候補を管理する。
class FriendsScreen extends StatefulWidget {
  final FriendProfile myProfile;

  /// フレンド名タップで対戦申込画面へ戻す場合の callback。
  /// null なら「対戦相手にする」ボタンを非表示にする。
  final void Function(FriendProfile friend)? onChooseAsOpponent;

  const FriendsScreen({
    super.key,
    required this.myProfile,
    this.onChooseAsOpponent,
  });

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _codeCtl = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _codeCtl.dispose();
    super.dispose();
  }

  Future<void> _addFriend() async {
    final code = _codeCtl.text.trim();
    if (code.isEmpty) return;
    setState(() => _adding = true);
    try {
      final p = await FirestoreSyncService.addFriendByCode(code);
      if (!mounted) return;
      _codeCtl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${p.displayName} を追加しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// 確認ダイアログを出してフレンドを削除する。
  ///
  /// 削除するのは自分の users/{uid}/friends/{相手} だけで、
  /// 相手のフレンド一覧からは自分は消えない（片方向）。
  /// 戻り値は実際に削除したかどうか（スワイプ削除の確定判定にも使う）。
  Future<bool> _confirmAndRemove(FriendProfile f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('フレンドを削除'),
        content: Text('${f.displayName} をフレンドから削除しますか？\n'
            'もう一度追加するにはコードの入力が必要です。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok != true) return false;

    try {
      await FirestoreSyncService.removeFriend(f.uid);
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${f.displayName} を削除しました')),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('削除に失敗: $e')),
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final myCode = widget.myProfile.code ?? '----';
    return Scaffold(
      appBar: AppBar(title: const Text('フレンド')),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('あなたのフレンドコード',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          myCode,
                          style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 3),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: 'コピー',
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: myCode));
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('コピーしました')),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeCtl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'フレンドコードを入力',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _adding ? null : _addFriend,
                  child: const Text('追加'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<List<FriendProfile>>(
              stream: FirestoreSyncService.watchFriends(),
              builder: (ctx, snap) {
                final list = snap.data ?? const <FriendProfile>[];
                if (list.isEmpty) {
                  return const Center(
                    child: Text('まだフレンドがいません',
                        style: TextStyle(color: Colors.black45)),
                  );
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final f = list[i];
                    // 左スワイプでも削除できる（確認ダイアログを挟む）。
                    return Dismissible(
                      key: ValueKey(f.uid),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) => _confirmAndRemove(f),
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: const Icon(Icons.delete_outline,
                            color: Colors.white),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(f.displayName.characters.first),
                        ),
                        title: Text(f.displayName),
                        subtitle: Text('コード: ${f.code ?? '----'}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.onChooseAsOpponent != null)
                              TextButton(
                                onPressed: () => widget.onChooseAsOpponent!(f),
                                child: const Text('対戦相手にする'),
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: '削除',
                              onPressed: () => _confirmAndRemove(f),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
