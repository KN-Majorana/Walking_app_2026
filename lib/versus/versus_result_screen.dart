import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../color_extraction.dart';
import '../current_location_marker.dart';
import '../models/battle.dart';
import '../models/polygon.dart';
import '../photo_pin.dart';
import '../photo_pin_marker.dart';
import '../services/area_share_calculator.dart';
import '../services/battle_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_sync_service.dart';
import 'dialogs/result_close_confirm_dialog.dart';
import 'versus_lobby_screen.dart';
import 'widgets/area_share_bar.dart';
import 'widgets/versus_polygons_overlay.dart';

/// リザルト画面（ended / result_shown）。
///
///   - 画面上部：面積比 % バー
///   - 地図：active 中と同じ内容をそのまま表示（フリーズ処理なし、パン/ズーム可）
///   - 「多角形を作る」ボタンは非表示。書き込み系操作は全て disable。
///   - 画面下部：「リザルト画面を終了する」ボタン
class VersusResultScreen extends StatefulWidget {
  final String battleId;
  const VersusResultScreen({super.key, required this.battleId});

  @override
  State<VersusResultScreen> createState() => _VersusResultScreenState();
}

class _VersusResultScreenState extends State<VersusResultScreen> {
  final MapController _mapController = MapController();

  Battle? _battle;
  String? _myUid;
  final List<PhotoPin> _photoPins = [];
  final List<WalkPolygon> _polygons = [];

  StreamSubscription<Battle?>? _battleSub;
  StreamSubscription<List<WalkPolygon>>? _polygonSub;
  StreamSubscription<List<PhotoPin>>? _photoSub;

  bool _resultCloseDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _myUid = FirebaseAuthService.uid;
    _subscribe();
    // ended → result_shown（両者の画面が開いた時点で遷移）
    BattleService.markResultShown(widget.battleId);
  }

  @override
  void dispose() {
    _battleSub?.cancel();
    _polygonSub?.cancel();
    _photoSub?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _battleSub = BattleService.watchBattle(widget.battleId).listen((b) async {
      if (!mounted) return;
      if (b == null) {
        // cleared → 対戦データが完全消去された。ローカル写真も消してロビーへ。
        await FirestoreSyncService.purgeBattleLocal(widget.battleId);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const VersusLobbyScreen()),
          (_) => false,
        );
        return;
      }
      setState(() => _battle = b);
      if (b.status == BattleStatus.cleared) {
        await FirestoreSyncService.purgeBattleLocal(widget.battleId);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const VersusLobbyScreen()),
          (_) => false,
        );
        return;
      }
      // 相手からのリザルト終了リクエスト
      final me = _myUid;
      if (b.status == BattleStatus.resultShown &&
          b.resultCloseRequestBy != null &&
          b.resultCloseRequestBy != me &&
          !_resultCloseDialogOpen) {
        _showResultCloseDialog();
      }
    });

    _polygonSub =
        FirestoreSyncService.watchBattlePolygons(widget.battleId).listen((list) {
      if (!mounted) return;
      setState(() {
        _polygons
          ..clear()
          ..addAll(list);
      });
    });

    _photoSub =
        FirestoreSyncService.watchBattlePhotos(widget.battleId).listen((list) {
      if (!mounted) return;
      setState(() {
        _photoPins
          ..clear()
          ..addAll(list);
      });
    });
  }

  Future<void> _showResultCloseDialog() async {
    _resultCloseDialogOpen = true;
    try {
      final ok = await ResultCloseConfirmDialog.show(context);
      if (!mounted) return;
      if (ok == true) {
        await BattleService.confirmResultClose(widget.battleId);
      } else if (ok == false) {
        await BattleService.cancelResultClose(widget.battleId);
      }
    } finally {
      _resultCloseDialogOpen = false;
    }
  }

  Future<void> _requestResultClose() async {
    final me = _myUid;
    if (me == null) return;
    await BattleService.requestResultClose(
        battleId: widget.battleId, byUid: me);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => AlertDialog(
        title: const Text('相手に確認中…'),
        content: const Text('対戦相手の応答を待っています'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(dctx).pop();
              await BattleService.cancelResultClose(widget.battleId);
            },
            child: const Text('キャンセル'),
          ),
        ],
      ),
    );
  }

  Color _colorFromId(int? id) {
    if (id == null || id < 0 || id >= colorPalette24.length) {
      return Colors.grey;
    }
    final c = colorPalette24[id];
    return Color.fromRGBO(c.r, c.g, c.b, 1);
  }

  @override
  Widget build(BuildContext context) {
    final b = _battle;
    final myUid = _myUid;
    if (b == null || myUid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final myColor = _colorFromId(b.myColorId(myUid));
    final oppColor = _colorFromId(b.oppColorId(myUid));

    final share = AreaShareCalculator.compute(
      polygons: _polygons,
      myUid: myUid,
      oppUid: b.opponentOf(myUid),
    );

    // 相手のピンは表示しない（active と同一のルール）
    final myPins = _photoPins.where((p) => p.ownerUid == myUid).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('対戦結果'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // 面積比 % バー
          AreaShareBar(
            myColor: myColor,
            opponentColor: oppColor,
            myPercent: share.myPercent,
            opponentPercent: share.opponentPercent,
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: const MapOptions(
                initialCenter: LatLng(35.1815, 136.9066),
                initialZoom: 13,
                minZoom: 3,
                maxZoom: 19,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.RunnerTests',
                  maxZoom: 19,
                ),
                // ★ 対戦ポリゴン描画（Demotest3-3 方式 + 実行時視覚的減算）
                //   A∩B は常に A（新しい方）の色のみで塗られる。
                VersusPolygonsOverlay(
                  polygons: _polygons,
                  myUid: myUid,
                ),
                MarkerLayer(
                  markers: [
                    for (final pin in myPins)
                      Marker(
                        point: pin.position,
                        width: 56,
                        height: 56,
                        child: GestureDetector(
                          onTap: () {
                            if (!pin.hasImageOnDevice ||
                                pin.imagePath.isEmpty) {
                              return;
                            }
                            showDialog<void>(
                              context: context,
                              builder: (_) => Dialog(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(File(pin.imagePath)),
                                ),
                              ),
                            );
                          },
                          child: Opacity(
                            opacity: pin.isDetached ? 0.45 : 1.0,
                            child: PhotoPinMarker(imagePath: pin.imagePath),
                          ),
                        ),
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: const [
                    // 現在地マーカーは非表示でもよいが、ユーザ位置感を残すため簡易表示
                    Marker(
                      point: LatLng(0, 0),
                      width: 0,
                      height: 0,
                      child: CurrentLocationMarker(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: _requestResultClose,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('リザルト画面を終了する'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
