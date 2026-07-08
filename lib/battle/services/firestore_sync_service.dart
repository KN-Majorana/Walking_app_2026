import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../models/friend_profile.dart';
import '../models/polygon.dart';
import '../photo_pin.dart';
import 'battle_service.dart';
import 'firebase_auth_service.dart';
import 'photo_pin_storage_service.dart';
import 'polygon_clip_service.dart';
import 'polygon_overlap_service.dart';

/// 対戦モードでの Firestore データ同期を担うサービス。
///
/// スキーマ:
///   users/{uid}                              : displayName, code, createdAt
///   users/{uid}/friends/{friendUid}          : addedAt, displayName, code
///   battles/{battleId}                        : status, challengerUid,
///                                                opponentUid, ...（BattleService 参照）
///   battles/{battleId}/polygons/{polygonId}   : ownerUid, ownerName, colorId,
///                                                vertices[], holes[], createdAt,
///                                                lastModifiedAt, photoIds[],
///                                                subtractedBy
///   battles/{battleId}/photos/{photoId}       : ownerUid, polygonId(nullable),
///                                                lat, lng, takenAt, colorId,
///                                                isDetached, detachedAt
///
/// 写真の実ファイルは各端末のローカルのみ保管。Firestore にはメタデータのみ流す。
/// Cloud Storage は一切使わない（firebase_storage 依存は無し）。
class FirestoreSyncService {
  FirestoreSyncService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  // ─────────────────────────────────────────
  // ユーザ / プロフィール
  // ─────────────────────────────────────────

  /// users/{uid} を作成（無ければ）。code が無ければ採番する。
  /// 自分の FriendProfile を返す。
  static Future<FriendProfile> ensureUserDoc(String displayName) async {
    final uid = await FirebaseAuthService.ensureSignedIn();
    final ref = _users.doc(uid);
    final snap = await ref.get();

    String code;
    if (!snap.exists || snap.data()?['code'] == null) {
      code = await _generateUniqueCode();
      await ref.set({
        'displayName': displayName,
        'code': code,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      code = snap.data()!['code'] as String;
      if (displayName.isNotEmpty &&
          snap.data()?['displayName'] != displayName) {
        await ref.set({'displayName': displayName}, SetOptions(merge: true));
      }
    }

    await FirebaseAuthService.updateDisplayName(displayName);
    return FriendProfile(uid: uid, displayName: displayName, code: code);
  }

  static Future<void> setDisplayName(String displayName) async {
    final uid = FirebaseAuthService.uid;
    if (uid == null) return;
    await _users.doc(uid).set(
      {'displayName': displayName},
      SetOptions(merge: true),
    );
    await FirebaseAuthService.updateDisplayName(displayName);
  }

  static Future<FriendProfile?> getMyProfile() async {
    final uid = FirebaseAuthService.uid;
    if (uid == null) return null;
    final snap = await _users.doc(uid).get();
    if (!snap.exists) return null;
    return FriendProfile.fromMap(uid, snap.data()!);
  }

  static Future<FriendProfile?> getUserByUid(String uid) async {
    try {
      final snap = await _users.doc(uid).get();
      if (!snap.exists) return null;
      return FriendProfile.fromMap(uid, snap.data()!);
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────
  // フレンド
  // ─────────────────────────────────────────

  static Stream<List<FriendProfile>> watchFriends() {
    final uid = FirebaseAuthService.uid;
    if (uid == null) return Stream.value(const []);
    return _users.doc(uid).collection('friends').snapshots().map((snap) {
      final out = <FriendProfile>[];
      for (final d in snap.docs) {
        try {
          out.add(FriendProfile.fromMap(d.id, d.data()));
        } catch (_) {}
      }
      return out;
    });
  }

  static Future<FriendProfile> addFriendByCode(String code) async {
    final uid = await FirebaseAuthService.ensureSignedIn();
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) throw 'コードを入力してください';

    final q =
        await _users.where('code', isEqualTo: normalized).limit(1).get();
    if (q.docs.isEmpty) throw 'そのコードのユーザが見つかりません';
    final doc = q.docs.first;
    if (doc.id == uid) throw '自分自身は追加できません';

    final data = doc.data();
    await _users.doc(uid).collection('friends').doc(doc.id).set({
      'addedAt': FieldValue.serverTimestamp(),
      'displayName': data['displayName'] ?? '名無し',
      'code': data['code'],
    });

    return FriendProfile.fromMap(doc.id, data);
  }

  static Future<void> removeFriend(String friendUid) async {
    final uid = FirebaseAuthService.uid;
    if (uid == null) return;
    await _users.doc(uid).collection('friends').doc(friendUid).delete();
  }

  // ─────────────────────────────────────────
  // 対戦モード：多角形（battles/{battleId}/polygons）
  // ─────────────────────────────────────────

  static Stream<List<WalkPolygon>> watchBattlePolygons(String battleId) {
    return BattleService.polygonsOf(battleId)
        .orderBy('createdAt')
        .snapshots()
        .map((snap) {
      final out = <WalkPolygon>[];
      for (final d in snap.docs) {
        try {
          out.add(WalkPolygon.fromMap({'id': d.id, ...d.data()}));
        } catch (_) {}
      }
      return out;
    });
  }

  static Future<void> upsertBattlePolygon(
      String battleId, WalkPolygon polygon) async {
    await BattleService.polygonsOf(battleId).doc(polygon.id).set(polygon.toMap());
  }

  static Future<void> deleteBattlePolygon(
      String battleId, String polygonId) async {
    try {
      await BattleService.polygonsOf(battleId).doc(polygonId).delete();
    } catch (_) {}
  }

  // ─────────────────────────────────────────
  // 対戦モード：写真メタ（battles/{battleId}/photos）
  // ─────────────────────────────────────────

  static Stream<List<PhotoPin>> watchBattlePhotos(String battleId) {
    return BattleService.photosOf(battleId).snapshots().map((snap) {
      final out = <PhotoPin>[];
      for (final d in snap.docs) {
        try {
          out.add(PhotoPin.fromFirestoreMap({'id': d.id, ...d.data()}));
        } catch (_) {}
      }
      return out;
    });
  }

  static Future<void> upsertBattlePhoto(
      String battleId, PhotoPin pin) async {
    await BattleService.photosOf(battleId).doc(pin.id).set(pin.toFirestoreMap());
  }

  // ═════════════════════════════════════════════════════════
  // 減算適用（A で古い B 群を書き換え）
  //   - updatedSingle → その場更新
  //   - holed         → 穴を追加
  //   - consumed      → B を物理削除、全 PhotoPin を detached へ
  //   - split         → 元 B を削除し B1..Bn を独立 Doc として作成
  //                     Bn の createdAt は元 B から継承
  //   attached → detached 遷移は写真ドキュメントの
  //     polygonId → null / isDetached → true / detachedAt → now
  //   を **同一 batch** で書き込む。写真ファイル本体は **絶対に削除しない**。
  // ═════════════════════════════════════════════════════════

  static Map<String, dynamic> _llm(LatLng v) =>
      {'lat': v.latitude, 'lng': v.longitude};

  /// A の確定タイミングで、より古い B 群への減算を Firestore に反映する。
  /// 失敗時はリトライしない（次に新規多角形を確定させたときに再試行になる）。
  static Future<void> applyBattleOverride({
    required String battleId,
    required WalkPolygon a,
    required List<WalkPolygon> candidates,
    // 分割（別ドキュメント生成）を許可するか。
    //   cutter 側（新しい方の owner が相手を減算する経路）では true。
    //   victim 側（自分の多角形が新しい相手に食い込まれた分を自分へ反映する
    //   経路）では false にして、分割の二重生成を防ぐ（分割は cutter 側のみ）。
    bool allowSplit = true,
  }) async {
    final aRing = a.vertices;
    final aStamp = a.claimStamp;
    if (aRing.length < 3 || aStamp == null) return;

    for (final b in candidates) {
      try {
        if (b.id == a.id) continue;
        if (!b.confirmed || !b.isActive || b.claimStamp == null) continue;
        // A の方が新しく主張された場合のみ B を減算する（claimStamp 基準）。
        if (!aStamp.isAfter(b.claimStamp!)) continue;

        // ★ 方針A：減算の基準は「保存済み vertices」ではなく
        //   B に属する非detachedピンの座標（画像が無くても lat/lng は残る）
        //   の凸包から毎回再計算する。これにより過去の減算結果を
        //   破壊的に上書き累積して外周が歪む問題を防ぐ。
        final bBase = await _baseRingFromPins(battleId, b);
        if (bBase.length < 3) continue;
        if (!PolygonClipService.regionsOverlap(bBase, aRing)) continue;

        final outcome = PolygonClipService.classify(bBase, aRing);
        final now = DateTime.now().millisecondsSinceEpoch;

        switch (outcome.kind) {
          case SubtractKind.unchanged:
            break;

          case SubtractKind.updatedSingle:
            await _applyUpdatedSingle(
              battleId: battleId,
              b: b,
              newRing: outcome.single!,
              aRing: aRing,
              aId: a.id,
              now: now,
            );
            break;

          case SubtractKind.holed:
            await BattleService.polygonsOf(battleId).doc(b.id).set({
              // 外周はピン凸包で正規化（累積防止）。穴は視覚差分として保持。
              'vertices': bBase.map(_llm).toList(),
              'holes': [
                {'points': outcome.hole!.map(_llm).toList()}
              ],
              'lastModifiedAt': now,
              'subtractedBy': a.id,
            }, SetOptions(merge: true));
            break;

          case SubtractKind.consumed:
            await _consumeB(battleId: battleId, b: b, aId: a.id);
            break;

          case SubtractKind.split:
            // 分割は cutter 側でのみ実行（victim 側は分割せず、cutter に委ねる）。
            if (allowSplit) {
              await _splitB(
                battleId: battleId,
                b: b,
                pieces: outcome.pieces!,
                aRing: aRing,
                aId: a.id,
              );
            }
            break;
        }
      } catch (_) {
        // この B の失敗は他の B の処理を止めない
      }
    }
  }

  // ── updatedSingle：削れて残った頂点の写真を pieces 内へ再配置 ──
  static Future<void> _applyUpdatedSingle({
    required String battleId,
    required WalkPolygon b,
    required List<LatLng> newRing,
    required List<LatLng> aRing,
    required String aId,
    required int now,
  }) async {
    final photos = await _readAttachedPhotos(battleId, b.id);
    final batch = _db.batch();
    final polyRef = BattleService.polygonsOf(battleId).doc(b.id);

    final survivingIds = <String>[];
    for (final ph in photos) {
      // A の内側に入った点 → detached
      final inA = PolygonClipService.pointInRing(ph.position, aRing);
      if (inA) {
        batch.set(
            BattleService.photosOf(battleId).doc(ph.id),
            {
              'polygonId': null,
              'isDetached': true,
              'detachedAt': now,
            },
            SetOptions(merge: true));
      } else {
        survivingIds.add(ph.id);
      }
    }

    // ★ 外周は「幾何差分の実際の形（newRing）」を保存する。
    //   これが食い込まれた凹多角形（例：6頂点）で、見た目と一致する。
    //   累積歪みは起きない：次回の減算入力は毎回 _baseRingFromPins
    //   （ピン凸包）から作り直すため、保存済み vertices はフィードバック
    //   されない。
    batch.set(
        polyRef,
        {
          'vertices': newRing.map(_llm).toList(),
          // 累積した穴が残らないようクリア（視覚差分はオーバーレイが担う）。
          'holes': <dynamic>[],
          'photoIds': survivingIds,
          'lastModifiedAt': now,
          'subtractedBy': aId,
        },
        SetOptions(merge: true));

    await batch.commit();
  }

  /// 減算の基準となる外周リング（方針A）。
  /// その多角形に属する非detachedピンの座標（画像有無に関わらず lat/lng は
  /// Firestore に残る）の凸包を返す。ピンが3枚未満のときは保存済み
  /// [WalkPolygon.vertices] にフォールバックする（手動投入・旧データ対策）。
  static Future<List<LatLng>> _baseRingFromPins(
      String battleId, WalkPolygon b) async {
    final photos = await _readAttachedPhotos(battleId, b.id);
    final pts = <LatLng>[];
    for (final p in photos) {
      if (p.position.latitude == 0.0 && p.position.longitude == 0.0) continue;
      pts.add(p.position);
    }
    if (pts.length >= 3) {
      final hull = PolygonOverlapService.convexHull(pts);
      if (hull.length >= 3) return hull;
    }
    return b.vertices;
  }

  // ── consumed：B を物理削除、B に紐づく全 PhotoPin を detached へ ──
  static Future<void> _consumeB({
    required String battleId,
    required WalkPolygon b,
    required String aId,
  }) async {
    final photos = await _readAttachedPhotos(battleId, b.id);
    final batch = _db.batch();
    final polyRef = BattleService.polygonsOf(battleId).doc(b.id);
    batch.delete(polyRef);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final ph in photos) {
      batch.set(
          BattleService.photosOf(battleId).doc(ph.id),
          {
            'polygonId': null,
            'isDetached': true,
            'detachedAt': now,
          },
          SetOptions(merge: true));
    }
    await batch.commit();
  }

  // ── split：元 B を削除し、pieces を独立 Doc として作成、写真を振り分け ──
  static Future<void> _splitB({
    required String battleId,
    required WalkPolygon b,
    required List<List<LatLng>> pieces,
    required List<LatLng> aRing,
    required String aId,
  }) async {
    final photos = await _readAttachedPhotos(battleId, b.id);
    final now = DateTime.now().millisecondsSinceEpoch;
    final createdMs = b.createdAt?.millisecondsSinceEpoch;
    // 分裂ピースは親の claimStamp を継承する（減算されても主張時刻は変えない）。
    final claimMs = b.claimStamp?.millisecondsSinceEpoch ?? createdMs;

    // 新 ID
    final refs = List.generate(
        pieces.length, (_) => BattleService.polygonsOf(battleId).doc());
    final assigned = List.generate(pieces.length, (_) => <String>[]);
    final assignedPos = List.generate(pieces.length, (_) => <LatLng>[]);
    final detached = <PhotoPin>[];

    for (final ph in photos) {
      final inA = PolygonClipService.pointInRing(ph.position, aRing);
      if (inA) {
        detached.add(ph);
        continue;
      }
      int target = -1;
      for (int i = 0; i < pieces.length; i++) {
        if (PolygonClipService.pointInRing(ph.position, pieces[i])) {
          target = i;
          break;
        }
      }
      if (target < 0) target = _nearestPiece(ph.position, pieces);
      if (target >= 0) {
        assigned[target].add(ph.id);
        assignedPos[target].add(ph.position);
      } else {
        detached.add(ph);
      }
    }

    final batch = _db.batch();
    batch.delete(BattleService.polygonsOf(battleId).doc(b.id));

    for (int i = 0; i < pieces.length; i++) {
      // ★ 方針A：ピースの外周は、そのピースに割り当てられたピンの凸包にする
      //   （頂点＝ピン。3枚以上あるとき）。3枚未満なら幾何差分のピースを使う。
      List<LatLng> pieceRing;
      if (assignedPos[i].length >= 3) {
        final hull = PolygonOverlapService.convexHull(assignedPos[i]);
        pieceRing = hull.length >= 3 ? hull : pieces[i];
      } else {
        pieceRing = pieces[i];
      }
      batch.set(refs[i], {
        'id': refs[i].id,
        'ownerUid': b.ownerUid,
        'ownerName': b.ownerName,
        'colorId': b.colorId,
        'vertices': pieceRing.map(_llm).toList(),
        'holes': <dynamic>[],
        // 元 B の createdAt / claimStamp を継承（減算判定の順序を保つため）
        'createdAt': createdMs,
        'claimedAt': claimMs,
        'lastModifiedAt': now,
        'subtractedBy': aId,
        'photoIds': assigned[i],
        'confirmed': true,
        'status': 'active',
      });
      for (final pid in assigned[i]) {
        batch.set(
            BattleService.photosOf(battleId).doc(pid),
            {'polygonId': refs[i].id},
            SetOptions(merge: true));
      }
    }
    for (final ph in detached) {
      batch.set(
          BattleService.photosOf(battleId).doc(ph.id),
          {
            'polygonId': null,
            'isDetached': true,
            'detachedAt': now,
          },
          SetOptions(merge: true));
    }

    await batch.commit();
    // 写真ファイル本体は削除しない（detached は残す）。
  }

  static int _nearestPiece(LatLng p, List<List<LatLng>> pieces) {
    int best = -1;
    double bestD = double.infinity;
    for (int i = 0; i < pieces.length; i++) {
      for (final v in pieces[i]) {
        final dx = p.longitude - v.longitude;
        final dy = p.latitude - v.latitude;
        final d = dx * dx + dy * dy;
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      }
    }
    return best;
  }

  static Future<List<PhotoPin>> _readAttachedPhotos(
      String battleId, String polygonId) async {
    final out = <PhotoPin>[];
    try {
      final q = await BattleService.photosOf(battleId)
          .where('polygonId', isEqualTo: polygonId)
          .get();
      for (final d in q.docs) {
        try {
          final ph = PhotoPin.fromFirestoreMap({'id': d.id, ...d.data()});
          if (!ph.isDetached) out.add(ph);
        } catch (_) {}
      }
    } catch (_) {}
    return out;
  }

  // ─────────────────────────────────────────
  // ローカル：battle 用写真ディレクトリ
  // ─────────────────────────────────────────

  /// 対戦中に撮った写真を保管するディレクトリ（端末ローカル）。
  static Future<Directory> battlePhotosDir(String battleId) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/battles/$battleId/photos');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// battle cleared 時の一括削除。ローカル写真ファイルもすべて消す。
  ///
  /// このメソッドは「頂点奪取時の detached 遷移トランザクション」とは
  /// 明確に分離されている：頂点奪取は写真ファイルを絶対に消さない。
  static Future<void> purgeBattleLocal(String battleId) async {
    try {
      final dir = await battlePhotosDir(battleId);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  /// 対戦終了時（cleared / 対戦ドキュメント消滅）に、端末に残る対戦データを
  /// すべて消去する。
  ///   * 写真の実ファイル（battles/{battleId}/photos/ ディレクトリ）
  ///   * 写真ピンのローカルミラー（photo_pins.json：座標・色などのメタ）
  /// 対戦モードは同時に1件しか成立しないため、ミラーは全消去でよい。
  static Future<void> purgeBattleLocalAll(String battleId) async {
    await purgeBattleLocal(battleId);
    try {
      await PhotoPinStorageService.clearAll();
    } catch (_) {}
  }

  // ─────────────────────────────────────────
  // 内部
  // ─────────────────────────────────────────

  static Future<String> _generateUniqueCode() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    for (int attempt = 0; attempt < 8; attempt++) {
      final code = List.generate(
        6,
        (_) => chars[rnd.nextInt(chars.length)],
      ).join();
      final exists =
          await _users.where('code', isEqualTo: code).limit(1).get();
      if (exists.docs.isEmpty) return code;
    }
    return 'X${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase().padLeft(5, '0').substring(0, 5)}';
  }
}
