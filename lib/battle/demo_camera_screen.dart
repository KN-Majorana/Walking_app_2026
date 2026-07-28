import 'package:flutter/material.dart';

import 'photo_service.dart';

/// 【デモ】実カメラの代わりに使う「偽カメラ」画面。
///
/// integration の対戦では「多角形を作る → 新しい多角形を作る → その場で撮影する」で
/// 実カメラが起動し、撮影するとその地点にピンが刺さる。デモではこのフローを
/// そのまま踏襲しつつ、実際の端末カメラは起動せず、画面には assets/demo_photos の
/// 指定画像を「カメラ越しに写っている」風に表示する。シャッターを押すと、その
/// 画像を実ファイルとして保存し、以降は通常の撮影写真と同じ経路でピンになる。
class DemoCameraScreen extends StatefulWidget {
  final String battleId;

  /// 割り当て色（colorPaletteBattle のインデックス）。6=青 / 0=赤。
  final int colorId;

  const DemoCameraScreen({
    super.key,
    required this.battleId,
    required this.colorId,
  });

  /// 青（challenger）が撮る写真。
  static const List<String> _bluePhotos = [
    'assets/demo_photos/blue_1.png',
    'assets/demo_photos/blue_2.png',
    'assets/demo_photos/blue_3.png',
  ];

  /// 赤（opponent）が撮る写真。
  static const List<String> _redPhotos = [
    'assets/demo_photos/red_1.png',
    'assets/demo_photos/red_2.png',
    'assets/demo_photos/red_3.png',
  ];

  /// 撮影ごとに順番に切り替えるためのカウンタ（色ごと）。
  static int _blueCount = 0;
  static int _redCount = 0;

  @override
  State<DemoCameraScreen> createState() => _DemoCameraScreenState();
}

class _DemoCameraScreenState extends State<DemoCameraScreen> {
  late final String _asset;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 色に応じて次の写真を選ぶ（撮影ごとに 1→2→3→1… と循環）。
    if (widget.colorId == 6) {
      _asset = DemoCameraScreen
          ._bluePhotos[DemoCameraScreen._blueCount % DemoCameraScreen._bluePhotos.length];
      DemoCameraScreen._blueCount++;
    } else {
      _asset = DemoCameraScreen
          ._redPhotos[DemoCameraScreen._redCount % DemoCameraScreen._redPhotos.length];
      DemoCameraScreen._redCount++;
    }
  }

  Future<void> _shoot() async {
    if (_saving) return;
    setState(() => _saving = true);
    final path =
        await PhotoService.saveAssetAsBattlePhoto(widget.battleId, _asset);
    if (!mounted) return;
    Navigator.of(context).pop(path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // カメラ越しに写っている風の被写体（demo_photos の指定画像）。
          Center(
            child: Image.asset(_asset, fit: BoxFit.contain),
          ),

          // 上部：カメラUI風のヘッダー（閉じる／ラベル）。
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.camera_alt,
                              color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text('カメラ',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 下部：シャッターボタン。
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: GestureDetector(
                  onTap: _saving ? null : _shoot,
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.white70, width: 4),
                    ),
                    child: _saving
                        ? const Padding(
                            padding: EdgeInsets.all(22),
                            child: CircularProgressIndicator(strokeWidth: 3),
                          )
                        : const Icon(Icons.circle,
                            color: Colors.white, size: 62),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
