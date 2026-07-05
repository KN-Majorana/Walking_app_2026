import 'package:cloud_firestore/cloud_firestore.dart';

/// 対戦（1v1 セッション）の状態。
///
///  idle → pending → active → ended → result_shown → cleared
///                  ↘ declined / expired
enum BattleStatus {
  pending,
  active,
  ended,
  resultShown,
  declined,
  expired,
  cleared,
}

extension BattleStatusX on BattleStatus {
  String get code {
    switch (this) {
      case BattleStatus.pending:
        return 'pending';
      case BattleStatus.active:
        return 'active';
      case BattleStatus.ended:
        return 'ended';
      case BattleStatus.resultShown:
        return 'result_shown';
      case BattleStatus.declined:
        return 'declined';
      case BattleStatus.expired:
        return 'expired';
      case BattleStatus.cleared:
        return 'cleared';
    }
  }

  static BattleStatus parse(String s) {
    switch (s) {
      case 'pending':
        return BattleStatus.pending;
      case 'active':
        return BattleStatus.active;
      case 'ended':
        return BattleStatus.ended;
      case 'result_shown':
        return BattleStatus.resultShown;
      case 'declined':
        return BattleStatus.declined;
      case 'expired':
        return BattleStatus.expired;
      case 'cleared':
        return BattleStatus.cleared;
      default:
        return BattleStatus.pending;
    }
  }
}

/// 対戦ドキュメント（battles/{battleId}）のドメインモデル。
class Battle {
  final String id;
  final BattleStatus status;
  final String challengerUid;
  final String opponentUid;
  final String? challengerName;
  final String? opponentName;

  final DateTime createdAt;

  /// pending の応答期限（createdAt + 5分）
  final DateTime? expiresAt;

  final DateTime? startedAt;
  final DateTime? endsAt;
  final DateTime? endedAt;

  /// 制限時間（秒）。デフォルト 3600。
  final int timeLimitSec;

  /// active 遷移時に確定する色割当
  final int? challengerColorId;
  final int? opponentColorId;

  /// 強制終了リクエスト
  final String? forceEndRequestBy;
  final DateTime? forceEndRequestAt;

  /// リザルト画面終了リクエスト
  final String? resultCloseRequestBy;
  final DateTime? resultCloseRequestAt;

  /// 終了理由（'forceEnd' | 'timeout'）
  final String? endedBy;

  const Battle({
    required this.id,
    required this.status,
    required this.challengerUid,
    required this.opponentUid,
    required this.createdAt,
    this.challengerName,
    this.opponentName,
    this.expiresAt,
    this.startedAt,
    this.endsAt,
    this.endedAt,
    this.timeLimitSec = 3600,
    this.challengerColorId,
    this.opponentColorId,
    this.forceEndRequestBy,
    this.forceEndRequestAt,
    this.resultCloseRequestBy,
    this.resultCloseRequestAt,
    this.endedBy,
  });

  /// 相手の UID を返す（[myUid] が参加者でない場合は空文字）。
  String opponentOf(String myUid) {
    if (myUid == challengerUid) return opponentUid;
    if (myUid == opponentUid) return challengerUid;
    return '';
  }

  /// 自分に割り当てられた色 ID
  int? myColorId(String myUid) {
    if (myUid == challengerUid) return challengerColorId;
    if (myUid == opponentUid) return opponentColorId;
    return null;
  }

  /// 相手に割り当てられた色 ID
  int? oppColorId(String myUid) {
    if (myUid == challengerUid) return opponentColorId;
    if (myUid == opponentUid) return challengerColorId;
    return null;
  }

  /// 自分から見た自分のプレイヤー名
  String? myName(String myUid) =>
      myUid == challengerUid ? challengerName : opponentName;

  /// 自分から見た相手のプレイヤー名
  String? oppName(String myUid) =>
      myUid == challengerUid ? opponentName : challengerName;

  bool get isActive => status == BattleStatus.active;
  bool get isEnded => status == BattleStatus.ended;
  bool get isResultShown => status == BattleStatus.resultShown;
  bool get isPending => status == BattleStatus.pending;

  /// endsAt を過ぎているか（クライアント時計基準）。
  bool get isPastEnd {
    final e = endsAt;
    if (e == null) return false;
    return DateTime.now().isAfter(e);
  }

  /// expiresAt を過ぎているか（クライアント時計基準）。
  bool get isExpiredPending {
    if (status != BattleStatus.pending) return false;
    final e = expiresAt;
    if (e == null) return false;
    return DateTime.now().isAfter(e);
  }

  Battle copyWith({
    BattleStatus? status,
    DateTime? startedAt,
    DateTime? endsAt,
    DateTime? endedAt,
    int? challengerColorId,
    int? opponentColorId,
    String? forceEndRequestBy,
    DateTime? forceEndRequestAt,
    String? resultCloseRequestBy,
    DateTime? resultCloseRequestAt,
    String? endedBy,
    String? challengerName,
    String? opponentName,
    int? timeLimitSec,
  }) {
    return Battle(
      id: id,
      status: status ?? this.status,
      challengerUid: challengerUid,
      opponentUid: opponentUid,
      challengerName: challengerName ?? this.challengerName,
      opponentName: opponentName ?? this.opponentName,
      createdAt: createdAt,
      expiresAt: expiresAt,
      startedAt: startedAt ?? this.startedAt,
      endsAt: endsAt ?? this.endsAt,
      endedAt: endedAt ?? this.endedAt,
      timeLimitSec: timeLimitSec ?? this.timeLimitSec,
      challengerColorId: challengerColorId ?? this.challengerColorId,
      opponentColorId: opponentColorId ?? this.opponentColorId,
      forceEndRequestBy: forceEndRequestBy ?? this.forceEndRequestBy,
      forceEndRequestAt: forceEndRequestAt ?? this.forceEndRequestAt,
      resultCloseRequestBy: resultCloseRequestBy ?? this.resultCloseRequestBy,
      resultCloseRequestAt: resultCloseRequestAt ?? this.resultCloseRequestAt,
      endedBy: endedBy ?? this.endedBy,
    );
  }

  Map<String, dynamic> toMap() => {
        'status': status.code,
        'challengerUid': challengerUid,
        'opponentUid': opponentUid,
        if (challengerName != null) 'challengerName': challengerName,
        if (opponentName != null) 'opponentName': opponentName,
        'createdAt': createdAt.millisecondsSinceEpoch,
        if (expiresAt != null) 'expiresAt': expiresAt!.millisecondsSinceEpoch,
        if (startedAt != null) 'startedAt': startedAt!.millisecondsSinceEpoch,
        if (endsAt != null) 'endsAt': endsAt!.millisecondsSinceEpoch,
        if (endedAt != null) 'endedAt': endedAt!.millisecondsSinceEpoch,
        'timeLimitSec': timeLimitSec,
        if (challengerColorId != null) 'challengerColorId': challengerColorId,
        if (opponentColorId != null) 'opponentColorId': opponentColorId,
        if (forceEndRequestBy != null) 'forceEndRequestBy': forceEndRequestBy,
        if (forceEndRequestAt != null)
          'forceEndRequestAt': forceEndRequestAt!.millisecondsSinceEpoch,
        if (resultCloseRequestBy != null)
          'resultCloseRequestBy': resultCloseRequestBy,
        if (resultCloseRequestAt != null)
          'resultCloseRequestAt': resultCloseRequestAt!.millisecondsSinceEpoch,
        if (endedBy != null) 'endedBy': endedBy,
      };

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    return null;
  }

  factory Battle.fromMap(String id, Map<String, dynamic> map) {
    return Battle(
      id: id,
      status: BattleStatusX.parse(map['status'] as String? ?? 'pending'),
      challengerUid: map['challengerUid'] as String? ?? '',
      opponentUid: map['opponentUid'] as String? ?? '',
      challengerName: map['challengerName'] as String?,
      opponentName: map['opponentName'] as String?,
      createdAt: _toDate(map['createdAt']) ?? DateTime.now(),
      expiresAt: _toDate(map['expiresAt']),
      startedAt: _toDate(map['startedAt']),
      endsAt: _toDate(map['endsAt']),
      endedAt: _toDate(map['endedAt']),
      timeLimitSec: (map['timeLimitSec'] as num?)?.toInt() ?? 3600,
      challengerColorId: (map['challengerColorId'] as num?)?.toInt(),
      opponentColorId: (map['opponentColorId'] as num?)?.toInt(),
      forceEndRequestBy: map['forceEndRequestBy'] as String?,
      forceEndRequestAt: _toDate(map['forceEndRequestAt']),
      resultCloseRequestBy: map['resultCloseRequestBy'] as String?,
      resultCloseRequestAt: _toDate(map['resultCloseRequestAt']),
      endedBy: map['endedBy'] as String?,
    );
  }
}
