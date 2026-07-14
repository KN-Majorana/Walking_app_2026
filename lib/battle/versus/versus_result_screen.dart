import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../color_extraction.dart';
import '../current_location_marker.dart';
import '../models/battle.dart';
import '../models/polygon.dart';
import '../photo_pin.dart';
import '../photo_pin_marker.dart';
import '../services/area_share_calculator.dart';
import '../services/battle_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_sync_service.dart';
import '../services/photo_pin_storage_service.dart';
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

  /// 端末ローカルに実画像を持つピンのキャッシュ（id → PhotoPin）。
  /// Firestore の写真メタには実画像パスが含まれないため、
  /// リザルト画面でもここから imagePath を復元しないと写真が表示されない。
  /// （active 画面と同じマージ方式）
  final Map<String, PhotoPin> _localImageCache = {};

  StreamSubscription<Battle?>? _battleSub;
  StreamSubscription<List<WalkPolygon>>? _polygonSub;
  StreamSubscription<List<PhotoPin>>? _photoSub;

  bool _resultCloseDialogOpen = false;

  // リザルト終了を申請した側（自分）の「相手に確認中…」待機ダイアログが開いているか。
  bool _resultCloseWaitingOpen = false;

  @override
  void initState() {
    super.initState();
    _myUid = FirebaseAuthService.uid;
    _loadLocalImages();
    _subscribe();
    // ended → result_shown（両者の画面が開いた時点で遷移）
    BattleService.markResultShown(widget.battleId);
  }

  /// 端末ローカルの写真ミラーを読み込み、実画像パスをキャッシュへ投入する。
  Future<void> _loadLocalImages() async {
    try {
      final localPins = await PhotoPinStorageService.loadAll();
      if (!mounted) return;
      setState(() {
        for (final p in localPins) {
          if (p.hasImageOnDevice) _localImageCache[p.id] = p;
        }
        // 既に Firestore から読み込み済みのピンにも画像をマージし直す。
        for (int i = 0; i < _photoPins.length; i++) {
          final cached = _localImageCache[_photoPins[i].id];
          if (cached != null && cached.hasImageOnDevice) {
            _photoPins[i] = cached.copyWith(
              polygonId: _photoPins[i].polygonId,
              isDetached: _photoPins[i].isDetached,
              detachedAt: _photoPins[i].detachedAt,
            );
          }
        }
      });
    } catch (_) {}
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
        // cleared → 対戦データが完全消去された。端末内の写真・座標も消してロビーへ。
        _dismissResultCloseWaiting();
        await FirestoreSyncService.purgeBattleLocalAll(widget.battleId);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const VersusLobbyScreen()),
          (_) => false,
        );
        return;
      }
      setState(() => _battle = b);
      // 自分が出したリザルト終了リクエストが解決した（相手が承認/拒否した）ら、
      // 申請側の「相手に確認中…」ダイアログを閉じる。
      if (_resultCloseWaitingOpen && b.resultCloseRequestBy != _myUid) {
        _dismissResultCloseWaiting();
      }
      if (b.status == BattleStatus.cleared) {
        _dismissResultCloseWaiting();
        await FirestoreSyncService.purgeBattleLocalAll(widget.battleId);
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
      // Firestore のメタ（polygonId / detached など）を正とし、実画像パスは
      // ローカルキャッシュ（_localImageCache）から復元してマージする。
      // これをしないと imagePath が空になり、写真が表示されない。
      final merged = <PhotoPin>[];
      for (final remote in list) {
        final cached = _localImageCache[remote.id];
        if (cached != null && cached.hasImageOnDevice) {
          merged.add(cached.copyWith(
            polygonId: remote.polygonId,
            isDetached: remote.isDetached,
            detachedAt: remote.detachedAt,
          ));
        } else {
          merged.add(remote);
        }
      }
      setState(() {
        _photoPins
          ..clear()
          ..addAll(merged);
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
    _resultCloseWaitingOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => AlertDialog(
        title: const Text('相手に確認中…'),
        content: const Text('対戦相手の応答を待っています'),
        actions: [
          TextButton(
            onPressed: () async {
              _resultCloseWaitingOpen = false;
              Navigator.of(dctx).pop();
              await BattleService.cancelResultClose(widget.battleId);
            },
            child: const Text('キャンセル'),
          ),
        ],
      ),
    );
    _resultCloseWaitingOpen = false;
  }

  /// 申請側の「相手に確認中…」待機ダイアログを閉じる（開いている場合のみ）。
  void _dismissResultCloseWaiting() {
    if (!_resultCloseWaitingOpen) return;
    _resultCloseWaitingOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Color _colorFromId(int? id) {
    if (id == null || id < 0 || id >= colorPaletteBattle.length) {
      return Colors.grey;
    }
    final c = colorPaletteBattle[id];
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
