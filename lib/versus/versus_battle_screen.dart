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

import '../color_extraction.dart';
import '../current_location_marker.dart';
import '../location_service.dart';
import '../models/battle.dart';
import '../models/polygon.dart';
import '../opponent_location_marker.dart';
import '../photo_pin.dart';
import '../photo_pin_marker.dart';
import '../polygon_create_flow.dart';
import '../services/battle_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_sync_service.dart';
import '../services/photo_pin_storage_service.dart';
import '../services/polygon_clip_service.dart';
import 'dialogs/force_end_confirm_dialog.dart';
import 'versus_lobby_screen.dart';
import 'versus_result_screen.dart';
import 'widgets/versus_polygons_overlay.dart';

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

  StreamSubscription<Battle?>? _battleSub;
  StreamSubscription<List<WalkPolygon>>? _polygonSub;
  StreamSubscription<List<PhotoPin>>? _photoSub;
  StreamSubscription<LatLng>? _posSub;
  Timer? _tick;

  /// 位置情報を Firestore へ上げる周期タイマー（既定 30 秒）。
  Timer? _locUploadTimer;
  static const Duration _locUploadInterval = Duration(seconds: 30);

  bool _forceEndDialogOpen = false;

  /// 減算リアクティブ処理の再入ガード（ストリーム連鎖による多重実行防止）。
  bool _reevaluating = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _battleSub?.cancel();
    _polygonSub?.cancel();
    _photoSub?.cancel();
    _posSub?.cancel();
    _tick?.cancel();
    _locUploadTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _myUid = FirebaseAuthService.uid;

    // ── 現在地のリアルタイム追従（背景取得対応）──
    //   位置ストリームを購読し、移動に応じて現在地マーカーを更新する。
    //   初回のみ地図を現在地へ寄せ、以降はユーザ操作を尊重する。
    try {
      _currentPosition = await LocationService.getCurrentPosition();
      _hasLocation = true;
      if (mounted) setState(() {});
      _mapController.move(_currentPosition, 15.0);
      _centeredOnce = true;
      // 起動直後に1度アップロード（相手側にすぐ表示させるため）。
      _uploadMyLocation();
    } catch (_) {}

    _posSub = LocationService.watchPosition().listen((pos) {
      if (!mounted) return;
      setState(() {
        _currentPosition = pos;
        _hasLocation = true;
      });
      if (!_centeredOnce) {
        _mapController.move(_currentPosition, 15.0);
        _centeredOnce = true;
      }
    });

    // ── 位置情報を一定間隔で Firestore へアップロード ──
    _locUploadTimer = Timer.periodic(_locUploadInterval, (_) {
      _uploadMyLocation();
    });

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

    // 起動時に既にローカルへ保存されている写真ピンを読み込む
    final localPins = await PhotoPinStorageService.loadAll();
    if (mounted) {
      setState(() {
        for (final p in localPins) {
          // 実画像を持つピンはキャッシュへ（消失防止）。
          if (p.hasImageOnDevice) _localImageCache[p.id] = p;
          if (_photoPins.any((e) => e.id == p.id)) continue;
          _photoPins.add(p);
        }
      });
    }
  }

  void _onBattle(Battle? b) {
    if (!mounted) return;
    if (b == null) {
      // cleared など → 端末内の対戦データ（写真・座標）を消してロビーへ。
      FirestoreSyncService.purgeBattleLocalAll(widget.battleId);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const VersusLobbyScreen()),
        (_) => false,
      );
      return;
    }
    setState(() => _battle = b);
    // 状態遷移に応じて画面を切り替える
    if (b.status == BattleStatus.ended || b.status == BattleStatus.resultShown) {
      // リザルト画面へ移動（result_shown 化は移動先で行う）
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
              await BattleService.cancelForceEnd(widget.battleId);
            },
            child: const Text('キャンセル'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveLocalMirror() async {
    try {
      await PhotoPinStorageService.saveAll(_photoPins);
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
        _toast(
            'あなたの色（${colorNames24[myColorId]}）と一致しないため追加できません');
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
      _toast('${colorNames24[myColorId]} のピンを追加しました（あと ${3 - pendingCount.length} 枚で多角形が確定）');
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

    _toast('${colorNames24[myColorId]} の多角形が確定しました');

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
    if (id == null || id < 0 || id >= colorPalette24.length) {
      return Colors.grey;
    }
    final c = colorPalette24[id];
    return Color.fromRGBO(c.r, c.g, c.b, 1);
  }

  String _mmss(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
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

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: 13,
              minZoom: 3,
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.RunnerTests',
                maxZoom: 19,
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

          // 左上：色バッジ
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
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
                            ? 'あなた: ${colorNames24[myColorId]}'
                            : 'あなた',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 上部中央：カウントダウン
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
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

          // 右上：強制終了ボタン
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
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

