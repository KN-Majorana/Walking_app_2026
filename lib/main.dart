import 'package:flutter/material.dart';

import 'loading_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 重い初期化（Documents パス解決・雲テクスチャ・Firebase・現在地）は
  // LoadingGate 側で行う。ここで待たないことで、起動直後すぐに
  // ローディング画面を描画できる（黒い画面の時間が出ない）。
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Map App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const LoadingGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}
