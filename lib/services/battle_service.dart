import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../color_extraction.dart';
import '../models/battle.dart';
import 'firebase_auth_service.dart';

/// 対戦（battle）ドキュメントの状態遷移コア。
///
/// 状態機械:
///   idle → pending → active → ended → result_shown → cleared
///                  ↘ declined / expired
///
/// 各遷移メソッドはトランザクションを使い、想定外の状態からの変更は失敗する。
class BattleService {
  BattleService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _battles =>
      _db.collection('battles');

  static DocumentReference<Map<String, dynamic>> battleRef(String battleId) =>
      _battles.doc(battleId);

  static CollectionReference<Map<String, dynamic>> polygonsOf(String battleId) =>
      _battles.doc(battleId).collection('polygons');

  static CollectionReference<Map<String, dynamic>> photosOf(String battleId) =>
      _battles.doc(battleId).collection('photos');

  // ─────────────────────────────────────────
  // 起動時：進行中 battle の検索
  // ─────────────────────────────────────────

  /// 現在ユーザに紐づく active / pending / ended / result_shown な battle を返す。
  /// 見つからなければ null。
  static Future<Battle?> findMyOngoingBattle() async {
    final uid = FirebaseAuthService.uid;
    if (uid == null) return null;

    // challengerUid / opponentUid の両方を検索
    final want = [
      BattleStatus.pending.code,
      BattleStatus.active.code,
      BattleStatus.ended.code,
      BattleStatus.resultShown.code,
    ];

    final asChallenger = await _battles
        .where('challengerUid', isEqualTo: uid)
        .where('status', whereIn: want)
        .limit(1)
        .get();
    if (asChallenger.docs.isNotEmpty) {
      final b = Battle.fromMap(
          asChallenger.docs.first.id, asChallenger.docs.first.data());
      if (b.isExpiredPending) {
        await _markExpired(b.id);
        return null;
      }
      return b;
    }

    final asOpponent = await _battles
        .where('opponentUid', isEqualTo: uid)
        .where('status', whereIn: want)
        .limit(1)
        .get();
    if (asOpponent.docs.isNotEmpty) {
      final b = Battle.fromMap(
          asOpponent.docs.first.id, asOpponent.docs.first.data());
      if (b.isExpiredPending) {
        await _markExpired(b.id);
        return null;
      }
      return b;
    }
    return null;
  }

  /// 特定 battle の変更を購読する。
  static Stream<Battle?> watchBattle(String battleId) {
    return _battles.doc(battleId).snapshots().map((s) {
      if (!s.exists) return null;
      return Battle.fromMap(s.id, s.data()!);
    });
  }

  /// 自分が opponentUid で pending の battle を購読（着信通知用）。
  static Stream<List<Battle>> watchIncomingChallenges(String myUid) {
    return _battles
        .where('opponentUid', isEqualTo: myUid)
        .where('status', isEqualTo: BattleStatus.pending.code)
        .snapshots()
        .map((snap) {
      final out = <Battle>[];
      for (final d in snap.docs) {
        try {
          final b = Battle.fromMap(d.id, d.data());
          if (b.isExpiredPending) continue;
          out.add(b);
        } catch (_) {}
      }
      return out;
    });
  }

  // ─────────────────────────────────────────
  // pending: 対決申込
  // ─────────────────────────────────────────

  /// A が B に対戦を申し込む。
  /// - 相手が既に active/pending の battle に居る場合は例外を投げる。
  /// - 自分が active/pending の battle に居る場合も例外を投げる。
  static Future<Battle> requestChallenge({
    required String challengerUid,
    required String challengerName,
    required String opponentUid,
    required String opponentName,
    int timeLimitSec = 3600,
  }) async {
    if (challengerUid == opponentUid) {
      throw '自分自身には対戦を申し込めません';
    }

    // 双方の同時対戦禁止チェック
    if (await _hasActiveOrPending(challengerUid)) {
      throw 'あなたは現在他の対戦中です';
    }
    if (await _hasActiveOrPending(opponentUid)) {
      throw '相手は現在対戦中です';
    }

    final now = DateTime.now();
    final ref = _battles.doc();
    final battle = Battle(
      id: ref.id,
      status: BattleStatus.pending,
      challengerUid: challengerUid,
      opponentUid: opponentUid,
      challengerName: challengerName,
      opponentName: opponentName,
      createdAt: now,
      expiresAt: now.add(const Duration(minutes: 5)),
      timeLimitSec: timeLimitSec,
    );
    await ref.set(battle.toMap());
    return battle;
  }

  /// A が自分の pending 申込をキャンセルする（battle ドキュメント削除）。
  static Future<void> cancelChallenge(String battleId) async {
    try {
      await _battles.doc(battleId).delete();
    } catch (_) {}
  }

  /// B が「対決する」を押して active へ遷移する。
  /// 色は colorPalette24 からランダムで 2 色を割り当てる（互いに異なる）。
  static Future<Battle> acceptChallenge(String battleId) async {
    final rnd = Random.secure();
    return _db.runTransaction<Battle>((tx) async {
      final ref = _battles.doc(battleId);
      final snap = await tx.get(ref);
      if (!snap.exists) throw '対戦が見つかりません';
      final b = Battle.fromMap(snap.id, snap.data()!);
      if (b.status != BattleStatus.pending) {
        throw '対戦は既に応答済みです';
      }
      if (b.isExpiredPending) {
        throw '対戦の応答期限が切れました';
      }

      final palette = colorPalette24.length;
      int a = rnd.nextInt(palette);
      int c = rnd.nextInt(palette);
      while (c == a) {
        c = rnd.nextInt(palette);
      }

      final now = DateTime.now();
      final endsAt = now.add(Duration(seconds: b.timeLimitSec));
      final updated = b.copyWith(
        status: BattleStatus.active,
        startedAt: now,
        endsAt: endsAt,
        challengerColorId: a,
        opponentColorId: c,
      );
      tx.update(ref, {
        'status': updated.status.code,
        'startedAt': now.millisecondsSinceEpoch,
        'endsAt': endsAt.millisecondsSinceEpoch,
        'challengerColorId': a,
        'opponentColorId': c,
      });
      return updated;
    });
  }

  /// B が「対決しない」を選ぶ → declined。
  static Future<void> declineChallenge(String battleId) async {
    await _battles.doc(battleId).update({
      'status': BattleStatus.declined.code,
    });
  }

  /// 応答期限切れの pending を expired にする。
  static Future<void> _markExpired(String battleId) async {
    try {
      await _battles.doc(battleId).update({
        'status': BattleStatus.expired.code,
      });
    } catch (_) {}
  }

  // ─────────────────────────────────────────
  // active → ended（時間切れ）
  // ─────────────────────────────────────────

  /// endsAt を過ぎたら ended へ遷移する（冪等）。
  static Future<void> maybeExpireByTime(String battleId) async {
    try {
      await _db.runTransaction((tx) async {
        final ref = _battles.doc(battleId);
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        final b = Battle.fromMap(snap.id, snap.data()!);
        if (b.status != BattleStatus.active) return;
        if (!b.isPastEnd) return;
        tx.update(ref, {
          'status': BattleStatus.ended.code,
          'endedAt': DateTime.now().millisecondsSinceEpoch,
          'endedBy': 'timeout',
        });
      });
    } catch (_) {}
  }

  // ─────────────────────────────────────────
  // 強制終了フロー（active → ended）
  // ─────────────────────────────────────────

  /// 強制終了を提案する（相手側の確認ポップアップの引き金）。
  static Future<void> requestForceEnd({
    required String battleId,
    required String byUid,
  }) async {
    await _battles.doc(battleId).update({
      'forceEndRequestBy': byUid,
      'forceEndRequestAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 相手が「終了する」を選択 → ended。
  static Future<void> confirmForceEnd(String battleId) async {
    await _db.runTransaction((tx) async {
      final ref = _battles.doc(battleId);
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final b = Battle.fromMap(snap.id, snap.data()!);
      if (b.status != BattleStatus.active) return;
      tx.update(ref, {
        'status': BattleStatus.ended.code,
        'endedAt': DateTime.now().millisecondsSinceEpoch,
        'endedBy': 'forceEnd',
        'forceEndRequestBy': FieldValue.delete(),
        'forceEndRequestAt': FieldValue.delete(),
      });
    });
  }

  /// 相手が「終了しない」を選択 → キャンセル、active 継続。
  static Future<void> cancelForceEnd(String battleId) async {
    await _battles.doc(battleId).update({
      'forceEndRequestBy': FieldValue.delete(),
      'forceEndRequestAt': FieldValue.delete(),
    });
  }

  // ─────────────────────────────────────────
  // ended → result_shown
  // ─────────────────────────────────────────

  /// ended になった直後、リザルト画面表示を開始したことを記録する（冪等）。
  static Future<void> markResultShown(String battleId) async {
    await _db.runTransaction((tx) async {
      final ref = _battles.doc(battleId);
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final b = Battle.fromMap(snap.id, snap.data()!);
      if (b.status == BattleStatus.ended) {
        tx.update(ref, {'status': BattleStatus.resultShown.code});
      }
    });
  }

  // ─────────────────────────────────────────
  // リザルト終了フロー（result_shown → cleared）
  // ─────────────────────────────────────────

  static Future<void> requestResultClose({
    required String battleId,
    required String byUid,
  }) async {
    await _battles.doc(battleId).update({
      'resultCloseRequestBy': byUid,
      'resultCloseRequestAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<void> cancelResultClose(String battleId) async {
    await _battles.doc(battleId).update({
      'resultCloseRequestBy': FieldValue.delete(),
      'resultCloseRequestAt': FieldValue.delete(),
    });
  }

  /// 相手が「終了する」を選択 → cleared にして battle と配下サブコレクションを消す。
  /// ローカル写真ファイルの削除は呼び出し側（FirestoreSyncService.purgeLocal）で行う。
  static Future<void> confirmResultClose(String battleId) async {
    // 1) status を cleared にする
    try {
      await _battles.doc(battleId).update({
        'status': BattleStatus.cleared.code,
      });
    } catch (_) {}

    // 2) サブコレクション（polygons / photos）を全削除
    await _purgeSubcollection(polygonsOf(battleId));
    await _purgeSubcollection(photosOf(battleId));

    // 3) battle 本体を物理削除
    try {
      await _battles.doc(battleId).delete();
    } catch (_) {}
  }

  /// 明示的に呼び出したい場合の purgeBattle。confirmResultClose と同等。
  static Future<void> purgeBattle(String battleId) async {
    await confirmResultClose(battleId);
  }

  static Future<void> _purgeSubcollection(
      CollectionReference<Map<String, dynamic>> col) async {
    try {
      final all = await col.get();
      // Firestore の batch は 500 op まで
      const chunk = 400;
      for (int i = 0; i < all.docs.length; i += chunk) {
        final batch = _db.batch();
        for (final d in all.docs.skip(i).take(chunk)) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────
  // 補助
  // ─────────────────────────────────────────

  /// [uid] が active か pending の battle を持っているか。
  static Future<bool> _hasActiveOrPending(String uid) async {
    Future<bool> hasIn(String field, String status) async {
      try {
        final q = await _battles
            .where(field, isEqualTo: uid)
            .where('status', isEqualTo: status)
            .limit(1)
            .get();
        if (q.docs.isEmpty) return false;
        final b = Battle.fromMap(q.docs.first.id, q.docs.first.data());
        if (b.isExpiredPending) {
          await _markExpired(b.id);
          return false;
        }
        return true;
      } catch (_) {
        return false;
      }
    }

    if (await hasIn('challengerUid', BattleStatus.active.code)) return true;
    if (await hasIn('challengerUid', BattleStatus.pending.code)) return true;
    if (await hasIn('opponentUid', BattleStatus.active.code)) return true;
    if (await hasIn('opponentUid', BattleStatus.pending.code)) return true;
    return false;
  }
}
