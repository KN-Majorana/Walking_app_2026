import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'models/battle.dart';
import 'services/battle_service.dart';
import 'services/firebase_auth_service.dart';
import 'services/firestore_sync_service.dart';
import 'versus/versus_battle_screen.dart';
import 'versus/versus_lobby_screen.dart';
import 'versus/versus_result_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 未捕捉の非同期エラーをログに出してアプリを継続させる安全網。
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    debugPrint('未捕捉エラー: $error\n$stack');
    return true;
  };

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase 初期化に失敗: $e');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '対戦マップ',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const _BootGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// 起動フロー：
///   1. Firebase 認証（匿名）
///   2. users/{uid} を作成／取得（displayName / code の採番）
///   3. 現在ユーザに紐づく進行中 battle（pending / active / ended /
///      result_shown）があれば該当画面へ直接遷移
///   4. 見つからなければロビー画面へ
class _BootGate extends StatefulWidget {
  const _BootGate();

  @override
  State<_BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<_BootGate> {
  Widget? _next;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final uid = await FirebaseAuthService.ensureSignedIn();
      final existing = await FirestoreSyncService.getMyProfile();
      final name = existing?.displayName ??
          'プレイヤー${uid.substring(uid.length - 4).toUpperCase()}';
      await FirestoreSyncService.ensureUserDoc(name);

      final battle = await BattleService.findMyOngoingBattle();
      if (!mounted) return;
      setState(() {
        _next = _screenForBattle(battle);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Widget _screenForBattle(Battle? b) {
    if (b == null) return const VersusLobbyScreen();
    switch (b.status) {
      case BattleStatus.pending:
        // pending の battle は lobby から待機ダイアログで扱われる想定だが、
        // 復帰時はロビーへ戻し、opponent 側は着信ポップアップで拾う。
        return const VersusLobbyScreen();
      case BattleStatus.active:
        return VersusBattleScreen(battleId: b.id);
      case BattleStatus.ended:
      case BattleStatus.resultShown:
        return VersusResultScreen(battleId: b.id);
      default:
        return const VersusLobbyScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text('接続に失敗しました\n$_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black87)),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _next = null;
                    });
                    _bootstrap();
                  },
                  child: const Text('再試行'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_next == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _next!;
  }
}
