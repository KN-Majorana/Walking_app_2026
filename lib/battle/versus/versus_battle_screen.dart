// ═════════════════════════════════════════════════════════════════════
// 対戦モード（active）画面。
//
// ★ 相手プレイヤーのピンは地図上に一切表示しない。
//   相手の存在は「相手の色で塗られた多角形」だけで可視化する。
//   Firestore の battle 配下 photos ドキュメント自体はデータ整合性のため
//   相手のものも同期されるが、UI 描画時にオーナ判定で除外する。
//   ゲーム性の含意：相手がどこにピンを置いたかは対戦中に一切分からない。
//   相手の色の多角形の出現・拡大でのみ相手の動きが可視化される。
// ═════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../battle_overlay.dart';
import '../../map_zoom.dart';
import '../../path_fog_overlay.dart';
import '../../services/map_fog_storage_service.dart';
import '../battle_mode_scope.dart';
import '../../color_extraction.dart';
import '../current_location_marker.dart';
import '../location_service.dart';
import '../models/battle.dart';
import '../models/polygon.dart';
import '../opponent_location_marker.dart';
import '../photo_pin.dart';
import '../photo_pin_marker.dart';
import '../polygon_create_flow.dart';
import '../../services/battle_photo_history_service.dart';
import '../services/battle_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_sync_service.dart';
import '../services/photo_pin_storage_service.dart';
import '../services/polygon_clip_service.dart';
import 'dialogs/force_end_confirm_dialog.dart';
import 'versus_lobby_screen.dart';
import 'versus_result_screen.dart';
import 'widgets/versus_polygons_overlay.dart';

/// モード切替バー（地図に重ねて表示）の高さ分、上部 UI を下げるための余白。
/// バー本体（約40px）＋上下パディング（16px×2）＝約72px に少し余裕を足した値。
const double _kModeBarSpace = 80;

class VersusBattleScreen extends StatefulWidget {
  final String battleId;
  const VersusBattleScreen({super.key, required this.battleId});

  @override
  State<VersusBattleScreen> createState() => _VersusBattleScreenState();
}

class _VersusBattleScreenState extends State<VersusBattleScreen> {
  final MapController _mapController = MapController();

  LatLng _currentPosition = const LatLng(35.1815, 136.9066);
  bool _hasLocation = false;

  /// 初回の位置取得で地図を現在地へ寄せたかどうか。
  /// 以降はユーザのパン/ズームを尊重し、自動追従はしない。
  bool _centeredOnce = false;

  Battle? _battle;
  String? _myUid;

  final List<PhotoPin> _photoPins = [];
  final List<WalkPolygon> _polygons = [];

  /// 端末ローカルに実画像を持つピンのキャッシュ（id → PhotoPin）。
  /// Firestore の写真ストリームで _photoPins を作り直す際、
  /// ここに実画像パスを保持しておくことで、
  ///   * まだ同期されていない pending ピン
  ///   * 同期途中で remote に一時的に含まれないピン
  /// が「消える／画像が失われる」のを防ぐ。作成時と起動時に投入し、
  /// 減算処理では消さない（battle 終了までは残す）。
  final Map<String, PhotoPin> _localImageCache = {};

  /// ローカルミラー（battle_photo_pins.json）の読み込みが完了したか。
  ///
  /// これが false の間に _saveLocalMirror() を走らせてはいけない。
  /// Firestore の初回スナップショットはローカル読み込みより先に届くことがあり、
  /// そのとき _localImageCache は空なので、マージ結果は imagePath が空の
  /// remote ピンだけになる。それをそのまま保存すると、端末に残っている
  /// 実画像へのパスがミラーから消え、再起動後に写真が失われる。
  bool _mirrorLoaded = false;

  StreamSubscription<Battle?>? _battleSub;
  StreamSubscription<List<WalkPolygon>>? _polygonSub;
  StreamSubscription<List<PhotoPin>>? _photoSub;
  StreamSubscription<LatLng>? _posSub;

  /// マップモードと同じ「これまでに霧を晴らした地点」。
  /// 対戦中もプレイヤー自身の地図（霧）をそのまま使うため、起動時に
  /// map_fog_cleared_points.json を読み込み、対戦中の通過点を追記していく。
  final List<LatLng> _fogClearedPoints = [];

  /// 表示だけに使う霧の消去点（歴代の対戦の軌跡・写真位置）。
  /// map_fog 側へは書き戻さないので、_fogClearedPoints とは分けて持つ。
  final List<LatLng> _fogHistoryPoints = [];

  /// 霧オーバーレイへ渡す全ての消去点。
  List<LatLng> get _fogPoints => [..._fogClearedPoints, ..._fogHistoryPoints];

  /// マップモードと同じ霧の消去半径（メートル）。
  /// 内側 _fogFullClearRadius までは完全に晴れ、外周はグラデーションで戻す。
  static const double _fogClearRadius = 30.0;
  static const double _fogFullClearRadius = 20.0;

  /// 直近の build 時の画面幅（論理ピクセル）。既定ズームの計算に使う。
  double _viewWidthPx = 400;

  /// 画面の端から端までが約 3km になるズームレベル（マップモードと共通）。
  double get _defaultZoom => MapZoom.forSpan(
        widthPx: _viewWidthPx,
        latitude: _currentPosition.latitude,
        spanMeters: kDefaultMapSpanMeters,
      );

  /// 直近で霧データを永続化した時点の点数（保存の間引き用）。
  int _fogSavedCount = 0;

  // 対戦中の移動軌跡（歴代データとして保存し、マップモードの霧晴らしに使う）
  final List<LatLng> _myTrail = [];
  int _trailFlushed = 0;
  Timer? _tick;

  /// 位置情報を Firestore へ上げる周期タイマー（既定 30 秒）。
  Timer? _locUploadTimer;
  static const Duration _locUploadInterval = Duration(seconds: 30);

  bool _forceEndDialogOpen = false;

  // 強制終了を申請した側（自分）の「相手に確認中…」待機ダイアログが開いているか。
  // 相手が承認/拒否したら、遷移前にこのダイアログを閉じる必要がある。
  bool _forceEndWaitingOpen = false;

  /// 減算リアクティブ処理の再入ガード（ストリーム連鎖による多重実行防止）。
  bool _reevaluating = false;

  @override
  void initState() {
    super.initState();
    // 対戦中は右端スワイプでマップへ戻れないようにする（誤操作防止）。
    // ロビー／リザルトへ遷移すると dispose で再び有効化される。
    BattleOverlay.swipeBackEnabled.value = false;
    _bootstrap();
  }

  @override
  void dispose() {
    BattleOverlay.swipeBackEnabled.value = true;
    _saveFogPoints();
    _flushTrail();
    _battleSub?.cancel();
    _polygonSub?.cancel();
    _photoSub?.cancel();
    _posSub?.cancel();
    _tick?.cancel();
    _locUploadTimer?.cancel();
    super.dispose();
  }

  /// 対戦中に晴らした霧を、マップモードと同じストレージへ永続化する。
  /// 対戦終了後もマップモードの地図に恒久的に反映される。
  void _saveFogPoints() {
    if (_fogClearedPoints.length == _fogSavedCount) return;
    _fogSavedCount = _fogClearedPoints.length;
    MapFogStorageService.saveAll(List.of(_fogClearedPoints));
  }

  /// 現在地を「霧を晴らした地点」として取り込む。
  ///
  /// マップモードでは「散歩を記録する」が押されている間だけ晴れるが、
  /// 対戦中は記録の有無に関わらず無条件で晴らす。
  /// 近すぎる点は間引いて、点数の肥大化を防ぐ。
  void _clearFogAt(LatLng pos) {
    const distance = Distance(roundResult: false);
    if (_fogClearedPoints.isNotEmpty &&
        distance(_fogClearedPoints.last, pos) < 8) {
      return;
    }
    _fogClearedPoints.add(pos);
    // 一定間隔でのみ保存し、書き込み頻度を抑える。
    if (_fogClearedPoints.length - _fogSavedCount >= 10) {
      _saveFogPoints();
    }
  }

  /// まだ保存していない移動軌跡を歴代データへ追記する。
  void _flushTrail() {
    if (_trailFlushed >= _myTrail.length) return;
    final newPoints = _myTrail.sublist(_trailFlushed);
    _trailFlushed = _myTrail.length;
    BattlePhotoHistoryService.appendTrajectory(newPoints);
  }

  /// 自分が対戦中に撮った写真を歴代データへ蓄積する（マップの霧晴らし用）。
  void _archiveMyPhotos(List<PhotoPin> pins) {
    final me = _myUid;
    if (me == null) return;
    final entries = pins
        .where((p) =>
            p.ownerUid == me && p.hasImageOnDevice && p.imagePath.isNotEmpty)
        .map((p) => (
              id: p.id,
              imagePath: p.imagePath,
              lat: p.position.latitude,
              lng: p.position.longitude,
              takenAt: p.takenAt,
            ))
        .toList();
    if (entries.isNotEmpty) {
      BattlePhotoHistoryService.appendEntries(entries);
    }
  }

  /// マップモードの霧データを読み込む。対戦中もプレイヤー自身の地図
  /// （散歩で晴らした場所＋歴代の対戦で通った場所）をそのまま使う。
  Future<void> _loadFogPoints() async {
    List<LatLng> saved = const [];
    List<LatLng> battleHistory = const [];
    try {
      saved = await MapFogStorageService.loadAll();
    } catch (_) {}
    try {
      // 歴代の対戦の軌跡・写真位置は常に霧晴らしへ反映する（設定は廃止）。
      battleHistory = await BattlePhotoHistoryService.loadFogPoints();
    } catch (_) {}
    _fogClearedPoints
      ..clear()
      ..addAll(saved);
    _fogHistoryPoints
      ..clear()
      ..addAll(battleHistory);
    // 読み込んだ時点の点数を「保存済み」として扱う（無変更なら書き戻さない）。
    _fogSavedCount = _fogClearedPoints.length;
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    _myUid = FirebaseAuthService.uid;

    // 自分の地図（霧）を先に用意する。
    await _loadFogPoints();

    // ── 現在地のリアルタイム追従（背景取得対応）──
    //   位置ストリームを購読し、移動に応じて現在地マーカーを更新する。
    //   初回のみ地図を現在地へ寄せ、以降はユーザ操作を尊重する。
    try {
      _currentPosition = await LocationService.getCurrentPosition();
      _hasLocation = true;
      // 対戦中は記録開始の有無に関わらず、通過地点の霧を無条件で晴らす。
      _clearFogAt(_currentPosition);
      if (mounted) setState(() {});
      _mapController.move(_currentPosition, _defaultZoom);
      _centeredOnce = true;
      // 起動直後に1度アップロード（相手側にすぐ表示させるため）。
      _uploadMyLocation();
    } catch (_) {}

    _posSub = LocationService.watchPosition().listen((pos) {
      if (!mounted) return;
      // 対戦中は無条件に、通過した場所の霧を晴らす。
      _clearFogAt(pos);
      setState(() {
        _currentPosition = pos;
        _hasLocation = true;
      });
      // 対戦中の移動軌跡を蓄積（歴代データ用）。
      _myTrail.add(pos);
      if (!_centeredOnce) {
        _mapController.move(_currentPosition, _defaultZoom);
        _centeredOnce = true;
      }
    });

    // ── 位置情報を一定間隔で Firestore へアップロード ──
    _locUploadTimer = Timer.periodic(_locUploadInterval, (_) {
      _uploadMyLocation();
      _flushTrail();
    });

    // ── ローカルミラーの読み込みは Firestore 購読より必ず先に行う ──
    //   逆順にすると、初回スナップショット処理時に _localImageCache が空で、
    //   imagePath を持たない remote ピンでミラーを上書きしてしまう
    //   （＝アプリのタスクを切ると写真が消える）。
    await _loadLocalMirror();

    // battle
    _battleSub = BattleService.watchBattle(widget.battleId).listen(_onBattle);

    // polygons / photos
    _polygonSub =
        FirestoreSyncService.watchBattlePolygons(widget.battleId).listen((list) {
      if (!mounted) return;
      setState(() {
        _polygons
          ..clear()
          ..addAll(list);
      });
      // ★ ポリゴン集合が変わるたびに減算を再評価する。
      //   claim 時（作成/頂点追加）だけでなく、相手の多角形が現れた/変わった
      //   瞬間にも「新しい方（＝自分の多角形）の owner 端末」が、より古い
      //   相手多角形を分割・別ドキュメント化する（相手が手動投入/別端末で
      //   置いた場合もカバー）。
      _reevaluateOverrides();
    });

    _photoSub =
        FirestoreSyncService.watchBattlePhotos(widget.battleId).listen((list) {
      if (!mounted) return;
      // Firestore 側のメタと、ローカルの実画像情報（imagePath / hasImageOnDevice）を
      // マージする。実画像は _localImageCache から復元することで、
      // 同期途中で remote に一時的に含まれないピンでも画像が失われない。
      final remoteIds = <String>{};
      final merged = <PhotoPin>[];
      for (final remote in list) {
        remoteIds.add(remote.id);
        final cached = _localImageCache[remote.id];
        if (cached != null && cached.hasImageOnDevice) {
          // 状態（polygonId / detached）は remote を正とし、画像はローカルを使う。
          merged.add(cached.copyWith(
            polygonId: remote.polygonId,
            isDetached: remote.isDetached,
            detachedAt: remote.detachedAt,
          ));
        } else {
          merged.add(remote);
        }
      }
      // まだ Firestore に無いローカルピン（pending 等）は消さずに保持する。
      for (final local in _localImageCache.values) {
        if (!remoteIds.contains(local.id) && local.hasImageOnDevice) {
          merged.add(local);
        }
      }
      setState(() {
        _photoPins
          ..clear()
          ..addAll(merged);
      });
      _saveLocalMirror();
      // 自分の写真を歴代データへ蓄積（マップモードの霧晴らし用）。
      _archiveMyPhotos(merged);
    });

    // 1 秒タイマー（残り時間 & endsAt 到達判定）
    _tick = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      setState(() {}); // 残り時間更新
      final b = _battle;
      if (b != null && b.status == BattleStatus.active && b.isPastEnd) {
        await BattleService.maybeExpireByTime(widget.battleId);
      }
    });

  }

  /// 起動時に、既にローカルへ保存されている写真ピンを読み込む。
  /// Firestore の購読を開始する前に必ず完了させること。
  Future<void> _loadLocalMirror() async {
    List<PhotoPin> localPins = const [];
    try {
      localPins = await PhotoPinStorageService.loadAll();
    } catch (_) {}

    // 実画像を持つピンはキャッシュへ（消失防止）。
    // mounted に関わらずキャッシュは必ず埋める（マージの正しさに直結するため）。
    for (final p in localPins) {
      if (p.hasImageOnDevice && p.imagePath.isNotEmpty) {
        _localImageCache[p.id] = p;
      }
    }
    _mirrorLoaded = true;

    if (!mounted) return;
    setState(() {
      for (final p in localPins) {
        if (_photoPins.any((e) => e.id == p.id)) continue;
        _photoPins.add(p);
      }
    });
  }

  void _onBattle(Battle? b) {
    if (!mounted) return;
    if (b == null) {
      // cleared など → 端末内の対戦データ（写真・座標）を消してロビーへ。
      _dismissForceEndWaiting();
      FirestoreSyncService.purgeBattleLocalAll(widget.battleId);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const VersusLobbyScreen()),
        (_) => false,
      );
      return;
    }
    setState(() => _battle = b);
    // 自分が出した強制終了リクエストが解決した（相手が承認/拒否した、または
    // リクエストが消えた）ら、申請側の「相手に確認中…」ダイアログを閉じる。
    if (_forceEndWaitingOpen && b.forceEndRequestBy != _myUid) {
      _dismissForceEndWaiting();
    }
    // 状態遷移に応じて画面を切り替える
    if (b.status == BattleStatus.ended || b.status == BattleStatus.resultShown) {
      // リザルト画面へ移動（result_shown 化は移動先で行う）
      _dismissForceEndWaiting();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => VersusResultScreen(battleId: widget.battleId),
        ),
      );
      return;
    }
    if (b.status == BattleStatus.declined ||
        b.status == BattleStatus.expired ||
        b.status == BattleStatus.cleared) {
      // 対戦終了 → 端末内の対戦データ（写真・座標）を消去してロビーへ。
      _dismissForceEndWaiting();
      FirestoreSyncService.purgeBattleLocalAll(widget.battleId);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const VersusLobbyScreen()),
        (_) => false,
      );
      return;
    }
    // active：強制終了リクエストの受信ポップアップ
    final myUid = _myUid;
    if (b.status == BattleStatus.active &&
        b.forceEndRequestBy != null &&
        b.forceEndRequestBy != myUid &&
        !_forceEndDialogOpen) {
      _showForceEndDialog();
    }
  }

  /// 申請側の「相手に確認中…」待機ダイアログを閉じる（開いている場合のみ）。
  void _dismissForceEndWaiting() {
    if (!_forceEndWaitingOpen) return;
    _forceEndWaitingOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _showForceEndDialog() async {
    _forceEndDialogOpen = true;
    try {
      final ok = await ForceEndConfirmDialog.show(context);
      if (!mounted) return;
      if (ok == true) {
        await BattleService.confirmForceEnd(widget.battleId);
      } else if (ok == false) {
        await BattleService.cancelForceEnd(widget.battleId);
      }
    } finally {
      _forceEndDialogOpen = false;
    }
  }

  Future<void> _requestForceEnd() async {
    final me = _myUid;
    if (me == null) return;
    await BattleService.requestForceEnd(battleId: widget.battleId, byUid: me);
    if (!mounted) return;
    // 提案者側の待機ダイアログ
    _forceEndWaitingOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => AlertDialog(
        title: const Text('相手に確認中…'),
        content: const Text('対戦相手の応答を待っています'),
        actions: [
          TextButton(
            onPressed: () async {
              _forceEndWaitingOpen = false;
              Navigator.of(dctx).pop();
              await BattleService.cancelForceEnd(widget.battleId);
            },
            child: const Text('キャンセル'),
          ),
        ],
      ),
    );
    _forceEndWaitingOpen = false;
  }

  Future<void> _saveLocalMirror() async {
    // 読み込み前の上書きは、ローカル画像パスの喪失に直結するので禁止。
    if (!_mirrorLoaded) return;
    try {
      // 実画像を持つローカル情報を必ず含めた形で保存する。
      // （remote 由来の pathless ピンで上書きしないための最終防衛線）
      final byId = <String, PhotoPin>{};
      for (final p in _photoPins) {
        byId[p.id] = p;
      }
      for (final cached in _localImageCache.values) {
        if (!cached.hasImageOnDevice || cached.imagePath.isEmpty) continue;
        final current = byId[cached.id];
        if (current == null) {
          byId[cached.id] = cached;
        } else if (!current.hasImageOnDevice || current.imagePath.isEmpty) {
          // 状態は current（remote 正）を維持し、画像だけローカルから補う。
          byId[cached.id] = current.copyWith(
            imagePath: cached.imagePath,
            hasImageOnDevice: true,
          );
        }
      }
      await PhotoPinStorageService.saveAll(byId.values.toList());
    } catch (_) {}
  }

  /// 自分の現在地を battle ドキュメントへ書き込む（対戦中のみ）。
  Future<void> _uploadMyLocation() async {
    final me = _myUid;
    final b = _battle;
    if (me == null || !_hasLocation) return;
    // active のときのみ共有する（終了後は不要）。
    if (b != null && b.status != BattleStatus.active) return;
    await BattleService.updateMyLocation(
      battleId: widget.battleId,
      uid: me,
      lat: _currentPosition.latitude,
      lng: _currentPosition.longitude,
    );
  }

  // ─── 「多角形を作る」ボタン押下 ───
  Future<void> _openCreatePolygonFlow() async {
    final b = _battle;
    final me = _myUid;
    if (b == null || me == null || b.status != BattleStatus.active) return;

    final myColorId = b.myColorId(me);
    if (myColorId == null) return;

    // 自分が確定済みで持っている多角形（自分の色に限定）
    final myConfirmed = _polygons
        .where((p) =>
            p.ownerUid == me &&
            p.confirmed &&
            p.isActive &&
            p.vertices.length >= 3)
        .toList();

    try {
      final result = await PolygonCreateFlow.runForVersus(
        context,
        myConfirmedPolygons: myConfirmed,
        currentPosition: _currentPosition,
        battleId: widget.battleId,
        assignedColorId: myColorId,
      );
      if (result == null) return;
      if (!mounted) return;

      if (result.usedLocationFallback) {
        _toast('位置情報が取得できなかったため、現在地・現在時刻で登録します');
      }
      if (!result.colorIds.contains(myColorId)) {
        // 色不一致 → ファイルを破棄
        try {
          await File(result.photoPath).delete();
        } catch (_) {}
        // 抽出された色を色名に変換（範囲外IDは除外）
        final detectedNames = result.colorIds
            .where((id) => id >= 0 && id < colorNamesBattle.length)
            .map((id) => colorNamesBattle[id])
            .join('、');
        final detectedText =
            detectedNames.isEmpty ? '色を検出できませんでした' : detectedNames;
        _toast(
            'あなたの色（${colorNamesBattle[myColorId]}）と一致しないため追加できません\n'
            '検出された色: $detectedText');
        return;
      }

      // ピンを追加してグループに attach
      if (result.kind == PolygonCreateKind.createNew) {
        await _createNewFlow(result, me, myColorId);
      } else {
        await _addExistingFlow(result, me, myColorId, myConfirmed);
      }
    } catch (e) {
      if (!mounted) return;
      _toast('追加に失敗: $e');
    }
  }

  // ── 新規多角形フロー ──
  Future<void> _createNewFlow(
    PolygonCreateResult r,
    String me,
    int myColorId,
  ) async {
    // pending グループ（同色・自分・polygonId==null かつ isDetached==false の
    // ピン群）を探す or 新規 ID を採番。
    //
    // detached ピンは pending 判定に含めない（除外フィルタ）。
    final pendingPins = _photoPins.where((p) =>
        p.ownerUid == me &&
        p.polygonId == null &&
        !p.isDetached && // ★ detached は 3 枚判定に含めない
        p.colorIds.contains(myColorId)).toList();

    // pending グループの polygonId は「未確定 ID」として仮採番。
    // 3 枚に到達したら Firestore へ polygon ドキュメントを作成する。
    String? tempGroupId;
    if (pendingPins.isNotEmpty) {
      // 既存 pending の groupId を再利用（先頭ピンの colorId + owner）
      tempGroupId = 'pending_${me}_$myColorId';
    } else {
      tempGroupId = 'pending_${me}_$myColorId';
    }

    // 新ピンをローカルに追加
    final pin = PhotoPin(
      imagePath: r.photoPath,
      position: r.position,
      takenAt: r.takenAt,
      colorIds: r.colorIds,
      ownerUid: me,
      polygonId: null, // pending
      hasImageOnDevice: true,
    );
    setState(() {
      _localImageCache[pin.id] = pin; // 実画像を保持（消失防止）
      _photoPins.add(pin);
    });
    await _saveLocalMirror();

    final pendingCount = _photoPins
        .where((p) =>
            p.ownerUid == me &&
            p.polygonId == null &&
            !p.isDetached &&
            p.colorIds.contains(myColorId))
        .toList();

    if (pendingCount.length < 3) {
      _toast('${colorNamesBattle[myColorId]} のピンを追加しました（あと ${3 - pendingCount.length} 枚で多角形が確定）');
      return;
    }

    // 3 枚以上 → 多角形を確定
    final positions = pendingCount.map((p) => p.position).toList();
    final hull = _convexHull(positions);
    final polyId = 'poly_${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now();
    final poly = WalkPolygon(
      id: polyId,
      ownerUid: me,
      ownerName: _battle?.myName(me) ?? '',
      colorId: myColorId,
      vertices: hull,
      createdAt: now,
      claimedAt: now, // 新規作成は「今」主張した扱い
      photoIds: pendingCount.map((p) => p.id).toList(),
      confirmed: true,
    );

    // ピンの polygonId を付け替え
    setState(() {
      for (int i = 0; i < _photoPins.length; i++) {
        if (pendingCount.any((p) => p.id == _photoPins[i].id)) {
          _photoPins[i] = _photoPins[i].copyWith(polygonId: polyId);
        }
      }
    });
    await _saveLocalMirror();

    // Firestore に反映
    await FirestoreSyncService.upsertBattlePolygon(widget.battleId, poly);
    for (final p in pendingCount) {
      final attached = p.copyWith(polygonId: polyId);
      await FirestoreSyncService.upsertBattlePhoto(widget.battleId, attached);
    }

    _toast('${colorNamesBattle[myColorId]} の多角形が確定しました');

    // 減算適用（より古く主張された B 群に対して、claimStamp 基準）
    final candidates = _polygons
        .where((p) =>
            p.id != polyId &&
            p.confirmed &&
            p.isActive &&
            p.claimStamp != null &&
            now.isAfter(p.claimStamp!))
        .toList();
    await FirestoreSyncService.applyBattleOverride(
      battleId: widget.battleId,
      a: poly,
      candidates: candidates,
    );
  }

  // ── 既存追加フロー（対象は自動選択）──
  Future<void> _addExistingFlow(
    PolygonCreateResult r,
    String me,
    int myColorId,
    List<WalkPolygon> myConfirmed,
  ) async {
    // 自分の色の多角形のみ候補
    final sameColor = myConfirmed.where((p) => p.colorId == myColorId).toList();
    if (sameColor.isEmpty) {
      try {
        await File(r.photoPath).delete();
      } catch (_) {}
      _toast('対象の多角形が見つかりません');
      return;
    }

    WalkPolygon? target;
    double best = double.infinity;
    for (final p in sameColor) {
      double d = double.infinity;
      // ★ 候補頂点集合は attached ピンのみ。detached ピンは除外。
      final attachedPos = _photoPins
          .where((ph) =>
              ph.polygonId == p.id &&
              !ph.isDetached &&
              ph.position.latitude != 0.0)
          .map((ph) => ph.position)
          .toList();
      // フォールバック：頂点座標を使う（Firestore の vertices）
      final iter = attachedPos.isNotEmpty ? attachedPos : p.vertices;
      for (final v in iter) {
        final dx = v.longitude - r.position.longitude;
        final dy = v.latitude - r.position.latitude;
        final sq = dx * dx + dy * dy;
        if (sq < d) d = sq;
      }
      if (d < best) {
        best = d;
        target = p;
      } else if (d == best &&
          target != null &&
          (p.claimStamp?.isAfter(target.claimStamp ?? DateTime(0)) ?? false)) {
        target = p;
      }
    }
    if (target == null) {
      try {
        await File(r.photoPath).delete();
      } catch (_) {}
      _toast('対象の多角形が見つかりません');
      return;
    }

    final pin = PhotoPin(
      imagePath: r.photoPath,
      position: r.position,
      takenAt: r.takenAt,
      colorIds: r.colorIds,
      ownerUid: me,
      polygonId: target.id,
      hasImageOnDevice: true,
    );
    final now = DateTime.now();
    // ★ 新頂点 X を「既存の頂点配列」に挿入する（凸包で作り直さない）。
    //   凸包にすると、相手に食い込まれてできた凹み頂点が捨てられてしまう。
    //   仕様：X に最も近い既存頂点を求め、その「次」との間に X を挿入する。
    //   例）[1,2,3,4,5] で最近傍が 3 なら → [1,2,3,X,4,5]。
    final newRing = _insertVertexNearest(target.vertices, r.position);
    final updated = target.copyWith(
      vertices: newRing,
      photoIds: [...target.photoIds, pin.id],
      // ★ 頂点追加は能動的な「主張」なので claimedAt を now に更新する。
      //   これで、この多角形が相手（例：赤）の新しい領域より前面に来て、
      //   多角形の内側が自分の色に塗り返される。
      claimedAt: now,
      lastModifiedAt: now,
    );

    setState(() {
      _localImageCache[pin.id] = pin; // 実画像を保持（消失防止）
      _photoPins.add(pin);
      final i = _polygons.indexWhere((p) => p.id == updated.id);
      if (i >= 0) _polygons[i] = updated;
    });
    await _saveLocalMirror();

    await FirestoreSyncService.upsertBattlePolygon(widget.battleId, updated);
    await FirestoreSyncService.upsertBattlePhoto(widget.battleId, pin);
    _toast('既存の多角形にピンを追加しました');

    // 頂点追加でも、より古く主張された B に減算がかかる（claimStamp 基準）。
    // updated.claimStamp は now なので、相手の赤も減算対象になり得る。
    final updatedStamp = updated.claimStamp ?? now;
    final candidates = _polygons
        .where((p) =>
            p.id != updated.id &&
            p.confirmed &&
            p.isActive &&
            p.claimStamp != null &&
            updatedStamp.isAfter(p.claimStamp!))
        .toList();
    await FirestoreSyncService.applyBattleOverride(
      battleId: widget.battleId,
      a: updated,
      candidates: candidates,
    );
  }

  // ─── 減算リアクティブ再評価 ───
  //   ポリゴン集合が更新されるたびに呼ばれる。自分（＝新しい方になり得る側）
  //   が owner の確定・active 多角形について、より古く主張された多角形を
  //   applyBattleOverride で減算・分割する。分割ピースの owner は被減算側
  //   （相手）のまま（_splitB が ownerUid を継承）。
  //
  //   ループ防止:
  //     * _reevaluating で再入を防ぐ。
  //     * 候補から「その A で既に処理済み（subtractedBy == a.id）」を除外する。
  //       claim 時の明示呼び出し（_createNewFlow/_addExistingFlow）はこの
  //       ガードを通さないので、青が成長したときは毎回きちんと再カットされる。
  Future<void> _reevaluateOverrides() async {
    if (_reevaluating) return;
    final me = _myUid;
    final b = _battle;
    if (me == null || b == null || b.status != BattleStatus.active) return;

    _reevaluating = true;
    try {
      // 自分が owner の確定・active・頂点3以上の多角形（＝減算する側 A）
      final mine = _polygons
          .where((p) =>
              p.ownerUid == me &&
              p.confirmed &&
              p.isActive &&
              p.claimStamp != null &&
              p.vertices.length >= 3)
          .toList();

      // ── cutter 側：自分（新しい方）が、より古い相手を減算・分割する ──
      for (final a in mine) {
        final candidates = _polygons
            .where((p) =>
                p.id != a.id &&
                p.confirmed &&
                p.isActive &&
                p.claimStamp != null &&
                a.claimStamp!.isAfter(p.claimStamp!) &&
                // ★ この A で既に減算済みの相手はスキップ（ストリーム連鎖の
                //   無限ループ防止）。
                p.subtractedBy != a.id)
            .toList();
        if (candidates.isEmpty) continue;
        await FirestoreSyncService.applyBattleOverride(
          battleId: widget.battleId,
          a: a,
          candidates: candidates,
        );
      }

      // ── victim 側：自分の多角形が「より新しい相手」に食い込まれた分を、
      //   自分のドキュメントへ反映する（相手に端末が無いデモでも、また
      //   相手が別端末で置いた場合でも、食い込み＝updatedSingle を永続化する）。
      //   分割は cutter 側に委ねる（allowSplit=false）ので二重生成しない。
      final newerOpponents = _polygons
          .where((p) =>
              p.ownerUid != me &&
              p.confirmed &&
              p.isActive &&
              p.claimStamp != null &&
              p.vertices.length >= 3)
          .toList();
      for (final a in newerOpponents) {
        final myVictims = mine
            .where((mp) =>
                mp.id != a.id &&
                a.claimStamp!.isAfter(mp.claimStamp!) &&
                // 既にこの A で減算済みの自分の多角形はスキップ（ループ防止）。
                mp.subtractedBy != a.id)
            .toList();
        if (myVictims.isEmpty) continue;
        await FirestoreSyncService.applyBattleOverride(
          battleId: widget.battleId,
          a: a,
          candidates: myVictims,
          allowSplit: false, // 分割は cutter 側のみ
        );
      }
    } catch (_) {
      // 失敗しても次のストリーム更新で再試行される
    } finally {
      _reevaluating = false;
    }
  }

  /// 既存の頂点リング [ring] に、新頂点 [x] を挿入して返す。
  /// [x] に最も近い「辺」（連続する2頂点の線分）を探し、その2頂点の間に
  /// 挿入する。これで x の方向へ自然に膨らみ、凹み（相手に食い込まれた形）を
  /// 保持したまま頂点を1つ増やせる。
  ///   例）辺(3,4) が最近傍なら ring=[1,2,3,4,5] → [1,2,3,X,4,5]
  /// （最近傍「頂点」の次に固定すると、x が逆側にあるとき不自然なスパイクに
  ///   なるため、最近傍「辺」に挿入する。）
  List<LatLng> _insertVertexNearest(List<LatLng> ring, LatLng x) {
    if (ring.length < 2) return [...ring, x];
    int bestEdge = 0;
    double best = double.infinity;
    for (int i = 0; i < ring.length; i++) {
      final a = ring[i];
      final b = ring[(i + 1) % ring.length];
      final d = _pointSegDist2(x, a, b);
      if (d < best) {
        best = d;
        bestEdge = i;
      }
    }
    final out = List<LatLng>.from(ring);
    out.insert(bestEdge + 1, x); // 最近傍の辺 (bestEdge, bestEdge+1) の間に挿入
    return out;
  }

  /// 点 p と線分 a-b の距離の二乗（x=lng, y=lat 平面）。
  double _pointSegDist2(LatLng p, LatLng a, LatLng b) {
    final dx = b.longitude - a.longitude;
    final dy = b.latitude - a.latitude;
    final len2 = dx * dx + dy * dy;
    double t = 0;
    if (len2 > 0) {
      t = ((p.longitude - a.longitude) * dx + (p.latitude - a.latitude) * dy) /
          len2;
      if (t < 0) t = 0;
      if (t > 1) t = 1;
    }
    final cx = a.longitude + t * dx;
    final cy = a.latitude + t * dy;
    final ex = p.longitude - cx;
    final ey = p.latitude - cy;
    return ex * ex + ey * ey;
  }

  List<LatLng> _convexHull(List<LatLng> points) {
    if (points.length < 3) return List<LatLng>.from(points);
    final pts = List<LatLng>.from(points)
      ..sort((a, b) => a.longitude != b.longitude
          ? a.longitude.compareTo(b.longitude)
          : a.latitude.compareTo(b.latitude));
    double cross(LatLng o, LatLng a, LatLng b) =>
        (a.longitude - o.longitude) * (b.latitude - o.latitude) -
        (a.latitude - o.latitude) * (b.longitude - o.longitude);
    final lower = <LatLng>[];
    for (final p in pts) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    final upper = <LatLng>[];
    for (final p in pts.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Color _colorFromId(int? id) {
    if (id == null || id < 0 || id >= colorPaletteBattle.length) {
      return Colors.grey;
    }
    final c = colorPaletteBattle[id];
    return Color.fromRGBO(c.r, c.g, c.b, 1);
  }

  String _mmss(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // 既定ズーム計算のため、現在の画面幅を控えておく。
    _viewWidthPx = MediaQuery.of(context).size.width;

    final b = _battle;
    final myUid = _myUid;

    if (b == null || myUid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final myColorId = b.myColorId(myUid);
    final myColor = _colorFromId(myColorId);
    final oppColor = _colorFromId(b.oppColorId(myUid));

    // 相手の最新位置（対戦中のみ表示）
    final oppLoc = b.status == BattleStatus.active ? b.oppLocation(myUid) : null;

    // 残り時間
    final ends = b.endsAt;
    final remaining = ends == null
        ? Duration.zero
        : ends.difference(DateTime.now());
    final displayRemain =
        remaining.isNegative ? Duration.zero : remaining;

    // ── 自分のピンのみ表示（★相手のピンは表示しない） ──
    final myPins = _photoPins.where((p) => p.ownerUid == myUid).toList();

    // モード切替バーが無い（マップからのオーバーレイ表示）ときは、
    // バー用に空けていた上部余白を詰める。
    final barPresent = BattleModeScope.isPresent(context);
    final topSpace = barPresent ? _kModeBarSpace : 12.0;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              // 画面の端から端までが実空間で約 3km になる倍率
              initialZoom: _defaultZoom,
              minZoom: 3,
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.RunnerTests',
                maxZoom: 19,
              ),
              // ── マップモードと同じ霧 ──
              //   自分がこれまでに歩いた場所（＋歴代の対戦の通過点）だけが
              //   晴れている状態から始まり、対戦中に通った場所も随時晴れる。
              //   通常のマップモードの写真ピンはここでは表示しない。
              PathFogOverlay(
                clearedPoints: _fogPoints,
                clearRadiusMeters: _fogClearRadius,
                fullClearRadiusMeters: _fogFullClearRadius,
              ),
              // ★ 対戦ポリゴン描画（Demotest3-3 方式 + 実行時視覚的減算）
              //   A∩B は常に A（新しい方）の色のみで塗られる。
              VersusPolygonsOverlay(
                polygons: _polygons,
                myUid: myUid,
              ),
              // 自分のピン（detached を含む。detached は透過率を下げて表示）
              MarkerLayer(
                markers: [
                  for (final pin in myPins)
                    Marker(
                      point: pin.position,
                      width: 56,
                      height: 56,
                      child: GestureDetector(
                        onTap: () {
                          if (!pin.hasImageOnDevice || pin.imagePath.isEmpty) {
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
                        // detached は透過率 45%、attached/pending は 100%。
                        // ★視覚差の採用方式：Opacity で全体を半透明化。
                        child: Opacity(
                          opacity: pin.isDetached ? 0.45 : 1.0,
                          child: PhotoPinMarker(imagePath: pin.imagePath),
                        ),
                      ),
                    ),
                ],
              ),
              // 相手の最新位置マーカー（常に最新の1点のみ）
              if (oppLoc != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: oppLoc.position,
                      width: 32,
                      height: 32,
                      child: OpponentLocationMarker(color: oppColor),
                    ),
                  ],
                ),
              if (_hasLocation)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition,
                      width: 13,
                      height: 13,
                      child: const CurrentLocationMarker(),
                    ),
                  ],
                ),
            ],
          ),

          // 左上：色バッジ（モード切替バーの下に来るよう上部を空ける）
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                    left: 12, right: 12, top: topSpace, bottom: 12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: myColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black26),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        myColorId != null
                            ? 'あなた: ${colorNamesBattle[myColorId]}'
                            : 'あなた',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 上部中央：カウントダウン（モード切替バーの下に配置）
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(top: topSpace),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _mmss(displayRemain),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 右上：強制終了ボタン（モード切替バーの下に配置）
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                    left: 12, right: 12, top: topSpace, bottom: 12),
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.black87),
                  onSelected: (v) {
                    if (v == 'forceEnd') _requestForceEnd();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'forceEnd',
                        child: Text('対決を強制終了する',
                            style: TextStyle(color: Colors.red))),
                  ],
                ),
              ),
            ),
          ),

          // 最上部中央：モード切替バー（地図に重ねて表示）
          // パディングはコラージュ/再生モード（map_screen 側の EdgeInsets.all(16)）と
          // 揃えて、モード間でバー位置が一致するようにしている。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(child: BattleModeScope.barOf(context)),
              ),
            ),
          ),
        ],
      ),

      // 右下：多角形を作るボタン
      floatingActionButton: FloatingActionButton(
        heroTag: 'create_polygon',
        tooltip: '多角形を作る',
        onPressed: _openCreatePolygonFlow,
        child: const Icon(Icons.brush),
      ),
    );
  }
}

