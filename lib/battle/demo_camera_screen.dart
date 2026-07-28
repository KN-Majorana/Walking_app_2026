import 'package:flutter/material.dart';

import 'photo_service.dart';

/// 【デモ】実カメラの代わりに使う「偽カメラ」画面。
///
/// integration の対戦では「多角形を作る → 新しい多角形を作る → その場で撮影する」で
/// 実カメラが起動し、撮影するとその地点にピンが刺さる。デモではこのフローを
/// そのまま踏襲しつつ、実際の端末カメラは起動せず、画面には assets/demo_photos の
/// 指定画像を「カメラ越しに写っている」風に表示する。シャッターを押すと、その
/// 画像を実ファイルとして保存し、以降は通常の撮影写真と同じ経路でピンになる。
///
/// 画面の見た目は iOS 標準カメラ（PHOTO モード）を模している。
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
  static const Color _iosYellow = Color(0xFFFFD60A);
  static const Color _iosGreen = Color(0xFF32D74B);

  late final String _asset;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 色に応じて次の写真を選ぶ（撮影ごとに 1→2→3→1… と循環）。
    if (widget.colorId == 6) {
      _asset = DemoCameraScreen._bluePhotos[
          DemoCameraScreen._blueCount % DemoCameraScreen._bluePhotos.length];
      DemoCameraScreen._blueCount++;
    } else {
      _asset = DemoCameraScreen._redPhotos[
          DemoCameraScreen._redCount % DemoCameraScreen._redPhotos.length];
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
      body: Column(
        children: [
          // ── 上部バー：緑の使用中インジケータ（中央）＋フラッシュ（右）──
          SafeArea(
            bottom: false,
            child: SizedBox(
              height: 46,
              child: Stack(
                children: [
                  const Align(
                    alignment: Alignment(0.08, 0),
                    child: _GreenDot(),
                  ),
                  Positioned(
                    right: 16,
                    top: 5,
                    child: _CircleButton(
                      icon: Icons.flash_auto,
                      onTap: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── プレビュー（4:3）＋ズーム表示 ──
          Expanded(
            child: Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: Colors.black)),
                Center(
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: ClipRect(
                      child: Image.asset(_asset, fit: BoxFit.cover),
                    ),
                  ),
                ),
                // ズーム（0.5 / 1×）。1× を選択状態として濃い丸で表示。
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 14,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: Text(
                            '0.5',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.45),
                          ),
                          child: const Text(
                            '1×',
                            style: TextStyle(
                              color: _iosYellow,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 下部：シャッター＋（閉じる / PHOTO / カメラ切替）──
          Container(
            color: Colors.black,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // シャッター（外リング＋内側の白丸）。
                    GestureDetector(
                      onTap: _saving ? null : _shoot,
                      child: Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                            child: _saving
                                ? const Padding(
                                    padding: EdgeInsets.all(18),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Colors.black45,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // 下段：閉じる / PHOTO / カメラ切替。
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _CircleButton(
                            icon: Icons.close,
                            onTap: _saving
                                ? () {}
                                : () => Navigator.of(context).pop(),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 7),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: const Text(
                              'PHOTO',
                              style: TextStyle(
                                color: _iosYellow,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          _CircleButton(
                            icon: Icons.autorenew,
                            onTap: () {},
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// iOS 使用中を示す小さな緑のドット。
class _GreenDot extends StatelessWidget {
  const _GreenDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: _DemoCameraScreenState._iosGreen,
      ),
    );
  }
}

/// 半透明の丸ボタン（フラッシュ / 閉じる / カメラ切替）。
class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.14),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
