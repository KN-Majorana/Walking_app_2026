import 'package:flutter/material.dart';

/// 対戦モード配下の各画面（ロビー / 対戦 / リザルト）へ、上位の map_screen が
/// 構築した「モード切替バー」を届けるためのスコープ。
///
/// これにより各画面が自分に最適な位置にバーを配置できる:
///   - 対戦画面 : 地図の上に重ねて上部中央に表示（既存 UI とは重ならない位置）
///   - ロビー / リザルト : 画面上部のバンドとして表示
class BattleModeScope extends InheritedWidget {
  /// 事前構築済みのモード切替バー（ModeSwitcher）。
  final Widget modeBar;

  const BattleModeScope({
    super.key,
    required this.modeBar,
    required super.child,
  });

  /// 配下の画面からモード切替バーを取得する。スコープが無い場合は空要素。
  static Widget barOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<BattleModeScope>();
    return scope?.modeBar ?? const SizedBox.shrink();
  }

  @override
  bool updateShouldNotify(BattleModeScope oldWidget) =>
      modeBar != oldWidget.modeBar;
}
