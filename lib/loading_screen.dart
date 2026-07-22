import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'battle/firebase_options.dart';
import 'fog_texture.dart';
import 'location_service.dart';
import 'map_screen.dart';
import 'services/app_paths.dart';

/// 起動時のローディング画面（スプラッシュ）。
///
/// アプリのタスクを切った状態から起動すると、初期化が終わるまでこの画面が
/// 表示され、準備ができたらマップ画面へ切り替わる。
///
/// ここで済ませる初期化:
///   * Documents ディレクトリの解決（画像パスの復元に必要）
///   * 霧の雲テクスチャの読み込み
///   * Firebase の初期化（失敗しても対戦モードが使えなくなるだけ）
///   * 現在地の先読み（地図が初期位置から飛ぶのを防ぐ）
///
/// これらを main() ではなくこの画面で行うことで、起動直後すぐに
/// スプラッシュを描画できる（真っ黒な待ち時間が出ない）。
class LoadingGate extends StatefulWidget {
  const LoadingGate({super.key});

  /// 背景画像。差し替えるときはこのパスのファイルを置き換える。
  static const String backgroundAsset = 'assets/launch/loading_source.png';

  /// 初期化が一瞬で終わっても、これだけは表示する（画面のちらつき防止）。
  static const Duration minimumDisplay = Duration(milliseconds: 1200);

  /// 位置情報の取得はここで打ち切る（電波の悪い場所で起動が止まらないように）。
  static const Duration locationTimeout = Duration(seconds: 5);

  @override
  State<LoadingGate> createState() => _LoadingGateState();
}

class _LoadingGateState extends State<LoadingGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _warmUp();
  }

  Future<void> _warmUp() async {
    final startedAt = DateTime.now();

    // 画像パスの相対保存／絶対復元に使う Documents ディレクトリ。
    try {
      await AppPaths.init();
    } catch (_) {}

    // 霧に使う雲テクスチャ（初回描画で使えるように先に用意する）。
    try {
      await FogTexture.load();
    } catch (_) {}

    // 対戦モード用の Firebase。失敗しても他モードは通常どおり動く。
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint('Firebase 初期化に失敗（対戦モードのみ無効になります）: $e');
    }

    // 現在地の先読み。取れなくても起動は続行する。
    try {
      await LocationService.getCurrentPosition()
          .timeout(LoadingGate.locationTimeout);
    } catch (_) {}

    // 表示時間が短すぎるとスプラッシュが一瞬光るだけになるので下限を設ける。
    final elapsed = DateTime.now().difference(startedAt);
    final remain = LoadingGate.minimumDisplay - elapsed;
    if (remain > Duration.zero) {
      await Future<void>.delayed(remain);
    }

    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      child: _ready ? const MapScreen() : const _LoadingView(),
    );
  }
}

/// スプラッシュの見た目。背景画像を全画面に敷き、下部にインジケータを置く。
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  /// 背景画像を読めなかったときのフォールバック配色。
  /// 実際の画像の上端・下端の色を拾って合わせてある。
  static const _fallbackGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFEFFBD5), Color(0xFFB1E5A0)],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 画像の下端の緑。上下に余りが出ても違和感が出ないようにしておく。
      backgroundColor: const Color(0xFFB1E5A0),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 背景（画面比率が違ってもトリミングで全面を覆う）
          Image.asset(
            LoadingGate.backgroundAsset,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const DecoratedBox(
              decoration: BoxDecoration(gradient: _fallbackGradient),
            ),
          ),

          // 下部：読み込み中の表示
          // 画像の下端は淡い緑地なので、濃い緑の文字で十分に読める。
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 64),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF2E7D32)),
                    ),
                  ),
                  SizedBox(height: 14),
                  Text(
                    '地図を準備しています',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF2E5B2E),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
