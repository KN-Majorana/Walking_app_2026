import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../battle/services/area_share_calculator.dart';
import '../battle/versus/widgets/area_share_bar.dart';
import '../battle/versus/widgets/versus_polygons_overlay.dart';
import '../stories_collage.dart';
import 'demo_config.dart';
import 'demo_engine.dart';
import 'demo_lobby_screen.dart';
import 'demo_photo_marker.dart';

/// リザルト画面のデモ版。
///
/// 本物と同じ [AreaShareBar]（面積比バー）と [VersusPolygonsOverlay]、
/// [AreaShareCalculator] を使い、対決終了時点の陣地の塗り分けと
/// 面積シェアを表示する。重なりは新しい方（青）に計上される。
///
/// 本物のリザルトと同様に、
///   * 画面（面積比バー＋地図）のスクリーンショットをカメラロールへ保存
///   * challenger（青）が撮った写真を自動でコラージュ（StoriesCollageScreen）
/// も行える。コラージュはアセット画像なので、一時ファイルへ書き出してから
/// 本物のコラージュ画面へ渡している。
class DemoResultScreen extends StatefulWidget {
  const DemoResultScreen({super.key});

  @override
  State<DemoResultScreen> createState() => _DemoResultScreenState();
}

class _DemoResultScreenState extends State<DemoResultScreen> {
  /// リザルト表示（面積比バー＋地図）のスクリーンショット用キー。
  final GlobalKey _resultShotKey = GlobalKey();
  bool _capturing = false;
  bool _buildingCollage = false;

  /// リザルト画面（面積比バー＋地図）をスクリーンショットしてカメラロールへ保存。
  Future<void> _captureResult() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final status = await Permission.photos.request();
      if (!status.isGranted && !status.isLimited) {
        _toast('写真ライブラリへのアクセスを許可してください');
        return;
      }
      final boundary = _resultShotKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final result = await ImageGallerySaver.saveImage(
        byteData.buffer.asUint8List(),
        quality: 100,
        name: 'battle_demo_result_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (!mounted) return;
      final ok = result['isSuccess'] == true;
      _toast(ok ? 'スクリーンショットを保存しました' : '保存に失敗しました');
    } catch (e) {
      _toast('エラー: $e');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// challenger（青）が撮った写真を自動コラージュした画面を開く。
  /// デモ写真はアセットなので、本物のコラージュ画面（Image.file 前提）へ
  /// 渡せるよう、一時ファイルへ書き出してからパスを渡す。
  Future<void> _openCollage() async {
    if (_buildingCollage) return;
    setState(() => _buildingCollage = true);
    try {
      final tmp = await getTemporaryDirectory();
      final paths = <String>[];
      for (final asset in DemoConfig.challengerPhotos) {
        final data = await rootBundle.load(asset);
        final name = asset.split('/').last;
        final file = File('${tmp.path}/demo_collage_$name');
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        paths.add(file.path);
      }
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StoriesCollageScreen(
            imagePaths: paths,
            title: '対戦コラージュ',
          ),
        ),
      );
    } catch (e) {
      _toast('コラージュの生成に失敗: $e');
    } finally {
      if (mounted) setState(() => _buildingCollage = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    // 対決終了時点（endSec）の状態で確定表示する。
    final t = DemoEngine.endSec;
    final polygons = DemoEngine.polygonsAt(t);
    final pins = DemoEngine.pinsAt(t);

    final share = AreaShareCalculator.compute(
      polygons: polygons,
      myUid: DemoConfig.challengerUid,
      oppUid: DemoConfig.opponentUid,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('対戦結果（デモ）'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: _capturing ? null : _captureResult,
            tooltip: 'スクリーンショットを保存',
            icon: _capturing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.camera_alt_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RepaintBoundary(
              key: _resultShotKey,
              child: Column(
                children: [
                  AreaShareBar(
                    myColor: DemoConfig.challengerColor,
                    opponentColor: DemoConfig.opponentColor,
                    myPercent: share.myPercent,
                    opponentPercent: share.opponentPercent,
                  ),
                  Expanded(
                    child: FlutterMap(
                      options: const MapOptions(
                        initialCenter: DemoConfig.mapCenter,
                        initialZoom: DemoConfig.mapZoom,
                        minZoom: 3,
                        maxZoom: 19,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.demo',
                          maxZoom: 19,
                        ),
                        VersusPolygonsOverlay(
                          polygons: polygons,
                          myUid: DemoConfig.challengerUid,
                        ),
                        MarkerLayer(
                          markers: [
                            for (final pin in pins)
                              Marker(
                                point: pin.position,
                                width: 54,
                                height: 54,
                                child: DemoPhotoMarker(
                                  asset: pin.asset,
                                  ringColor: pin.ownerUid ==
                                          DemoConfig.challengerUid
                                      ? DemoConfig.challengerColor
                                      : DemoConfig.opponentColor,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WinnerLine(share: share),
                  const SizedBox(height: 10),
                  // コラージュを生成（challenger が撮った写真を自動配置）
                  OutlinedButton.icon(
                    onPressed: _buildingCollage ? null : _openCollage,
                    icon: _buildingCollage
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: const Text('コラージュを生成'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                            builder: (_) => const DemoLobbyScreen()),
                        (_) => false,
                      );
                    },
                    icon: const Icon(Icons.replay),
                    label: const Text('ロビーに戻る'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
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

class _WinnerLine extends StatelessWidget {
  final AreaShareResult share;
  const _WinnerLine({required this.share});

  @override
  Widget build(BuildContext context) {
    final blueWins = share.myPercent >= share.opponentPercent;
    final text = blueWins ? '青(あなた)の勝ち！' : '赤(あいて)の勝ち！';
    final color =
        blueWins ? DemoConfig.challengerColor : DemoConfig.opponentColor;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.emoji_events, color: color),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}
