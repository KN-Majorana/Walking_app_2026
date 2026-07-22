import 'package:flutter/material.dart';

import '../battle_overlay.dart';
import '../tutorial_service.dart';
import 'models/battle.dart';
import 'services/battle_service.dart';
import 'services/firebase_auth_service.dart';
import 'services/firestore_sync_service.dart';
import 'versus/versus_battle_screen.dart';
import 'versus/versus_lobby_screen.dart';
import 'versus/versus_result_screen.dart';

/// 対戦モードのルート画面（Battle_Function_Ver2 統合）。
///
/// 元の `Battle_Function_Ver2/lib/main.dart` にあった `_BootGate` の
/// 起動フローをそのまま踏襲する:
///   1. Firebase 認証（匿名）
///   2. users/{uid} を作成／取得
///   3. 進行中 battle があれば該当画面へ直接遷移
///   4. 見つからなければロビー画面へ
///
/// Demotest2 側では単体の `MaterialApp` としてではなく、地図画面の
/// 「対戦」タブに埋め込むウィジェットとして使う。
class BattleRootScreen extends StatefulWidget {
  const BattleRootScreen({super.key});

  @override
  State<BattleRootScreen> createState() => _BattleRootScreenState();
}

class _BattleRootScreenState extends State<BattleRootScreen> {
  Widget? _next;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    // 対戦（オーバーレイ）に入ったときの初回チュートリアル。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) TutorialService.showForBattle(context);
    });
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
                Text(
                  '対戦モードへの接続に失敗しました\n$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black87),
                ),
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
    // 対戦フロー（ロビー→対戦→リザルト）を専用のネストされた Navigator 内で
    // 完結させる。こうすることで versus 画面群の pushReplacement /
    // pushAndRemoveUntil がアプリのルート Navigator ではなくこの内部 Navigator
    // に対して働き、上位（map_screen）のモード切替バーが常に表示され続ける。
    // ダイアログ類は rootNavigator: true を明示しているため影響を受けない。
    // 右端を左へスワイプするとマップモードへ戻る。
    // 対戦中（active）は BattleOverlay.swipeBackEnabled が false になるため、
    // ロビー／リザルトでのみ戻れる。
    return Stack(
      children: [
        Navigator(
          onGenerateInitialRoutes: (navigator, initialRoute) => [
            MaterialPageRoute(builder: (_) => _next!),
          ],
        ),
        ValueListenableBuilder<bool>(
          valueListenable: BattleOverlay.swipeBackEnabled,
          builder: (context, enabled, _) => EdgeSwipeDetector(
            fromLeft: false,
            enabled: enabled,
            onSwipe: () => BattleOverlay.close(context),
          ),
        ),
      ],
    );
  }
}
