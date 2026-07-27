import 'package:flutter/material.dart';

import 'demo/demo_lobby_screen.dart';

/// 対戦機能デモ（独立版）のエントリポイント。
///
/// このフォルダ（integration_Ver1_demo）は integration_Ver1 の対戦機能を
/// 1 台の端末で説明するためのデモ専用プロジェクト。通常アプリ（地図モード）
/// は起動せず、対戦ロビーから直接始まる。Firebase / GPS / 実カメラ /
/// OpenCV 色判定は使わず、challenger（青）と opponent（赤）を自動再生する。
///
/// 実行:
///   flutter pub get
///   flutter run
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
      home: const DemoLobbyScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
