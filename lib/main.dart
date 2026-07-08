import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'map_screen.dart';
import 'battle/firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 対戦モード用の Firebase 初期化。失敗しても他モードは通常通り動作する
  // （対戦モードのみ利用不可になる）。
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase 初期化に失敗（対戦モードのみ無効になります）: $e');
  }

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
      home: const MapScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
