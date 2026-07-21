import 'package:flutter/material.dart';

import 'battle/battle_root_screen.dart';

/// 対戦フロー（ロビー → 対戦 → リザルト）を、マップモードの上に重ねて
/// 全画面表示するためのオーバーレイ。
///
/// 対戦は独立したモードタブではなく「マップモードから呼び出す画面」になった。
///   * 開く   : マップモードで画面左端を右へスワイプ
///   * 閉じる : ロビー／リザルト画面で画面右端を左へスワイプ
///     （対戦中（active）は誤操作防止のため閉じられない）
///
/// 画面遷移はルート Navigator への push で行い、左から滑り込むアニメーション
/// を付ける。オーバーレイ内ではモード切替バーを出さない（BattleModeScope を
/// 張らないので、配下の `BattleModeScope.barOf` は空要素を返す）。
class BattleOverlay {
  BattleOverlay._();

  /// 対戦オーバーレイが表示中かどうか（多重 push の防止に使う）。
  static bool _open = false;
  static bool get isOpen => _open;

  /// 右端スワイプでオーバーレイを閉じられるか。
  ///
  /// ロビー／リザルトでは true、対戦中（active）は誤操作で対戦から抜けないよう
  /// VersusBattleScreen 側が false にする。
  static final ValueNotifier<bool> swipeBackEnabled = ValueNotifier<bool>(true);

  /// 対戦オーバーレイを開く。既に開いていれば何もしない。
  static Future<void> open(BuildContext context) async {
    if (_open) return;
    _open = true;
    // 開いた直後はロビーなので、戻るスワイプは有効から始める。
    swipeBackEnabled.value = true;
    try {
      await Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          opaque: true,
          barrierDismissible: false,
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, __, ___) => const BattleRootScreen(),
          transitionsBuilder: (_, animation, __, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(-1, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            );
          },
        ),
      );
    } finally {
      _open = false;
    }
  }

  /// 対戦オーバーレイを閉じてマップモードへ戻る。
  static void close(BuildContext context) {
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) nav.pop();
  }
}

/// 画面端からのスワイプを検出する透明なジェスチャ領域。
///
/// 地図（FlutterMap）のパン操作と競合しないよう、検出幅は端から
/// [edgeWidth] ピクセルに限定し、`HitTestBehavior.translucent` で
/// 下位のウィジェットにもイベントを渡す。
class EdgeSwipeDetector extends StatefulWidget {
  /// 左端から右へのスワイプを検出する（false なら右端から左へ）。
  final bool fromLeft;

  /// 検出対象とする画面端の幅（論理ピクセル）。
  final double edgeWidth;

  /// スワイプ成立と判定する最小移動量。
  final double triggerDistance;

  /// 有効かどうか。false のときはジェスチャを一切拾わない。
  final bool enabled;

  final VoidCallback onSwipe;

  const EdgeSwipeDetector({
    super.key,
    required this.fromLeft,
    required this.onSwipe,
    this.edgeWidth = 24,
    this.triggerDistance = 48,
    this.enabled = true,
  });

  @override
  State<EdgeSwipeDetector> createState() => _EdgeSwipeDetectorState();
}

class _EdgeSwipeDetectorState extends State<EdgeSwipeDetector> {
  double _dx = 0;
  bool _fired = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();

    return Positioned(
      top: 0,
      bottom: 0,
      left: widget.fromLeft ? 0 : null,
      right: widget.fromLeft ? null : 0,
      width: widget.edgeWidth,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) {
          _dx = 0;
          _fired = false;
        },
        onHorizontalDragUpdate: (details) {
          if (_fired) return;
          _dx += details.delta.dx;
          final progressed = widget.fromLeft ? _dx : -_dx;
          if (progressed >= widget.triggerDistance) {
            _fired = true;
            widget.onSwipe();
          }
        },
        onHorizontalDragEnd: (_) {
          _dx = 0;
          _fired = false;
        },
      ),
    );
  }
}
