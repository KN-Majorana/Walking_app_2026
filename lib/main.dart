import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'battle/firebase_options.dart';
import 'battle/versus/versus_lobby_screen.dart';
import 'fog_texture.dart';
import 'services/app_paths.dart';

/// 対戦機能デモのエントリポイント。
///
/// このデモは integration の「対戦機能」を紹介する動画を作るためのもの。
/// アプリの中身（ロビー / 対戦 / リザルト / Firebase 同期）は integration と
/// 同一で、実際に 2 台の端末が Firebase 経由で対戦する。デモ用の差分は
///   * 色は固定（Challenger=青 / Opponent=赤）で自動開始
///   * 制限時間はどれを選んでも 15 分
///   * 移動はプリセット経路の自動再生（再生速度は Opponent 端末が制御し同期）
///   * カメラは実カメラではなく demo_photos の画像を映す偽カメラ
/// のみ。通常アプリ（地図モード）は起動せず、対戦ロビーから直接始まる。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '対戦デモ',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const _DemoLoadingGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// 起動時の初期化ゲート。integration の LoadingGate と同じ初期化を行い、
/// 準備ができたら対戦ロビー（integration の VersusLobbyScreen）へ切り替える。
class _DemoLoadingGate extends StatefulWidget {
  const _DemoLoadingGate();

  @override
  State<_DemoLoadingGate> createState() => _DemoLoadingGateState();
}

class _DemoLoadingGateState extends State<_DemoLoadingGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _warmUp();
  }

  Future<void> _warmUp() async {
    // 画像パスの保存／復元に使う Documents ディレクトリ。
    try {
      await AppPaths.init();
    } catch (_) {}

    // 霧の雲テクスチャ（対戦画面の霧描画で使う）。
    try {
      await FogTexture.load();
    } catch (_) {}

    // 対戦モード用の Firebase。
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint('Firebase 初期化に失敗: $e');
    }

    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return const VersusLobbyScreen();
  }
}
