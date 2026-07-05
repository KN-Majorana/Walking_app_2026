import 'package:latlong2/latlong.dart';

/// 多角形（陣地）のドメインモデル。
///
/// 注: flutter_map も `Polygon` をエクスポートしているため、名前衝突を
/// 避けてクラス名は [WalkPolygon] とする。
///
/// v4 で MultiPolygon（rings）表現を撤廃し、**単一の外周リング**
/// ([vertices]) ＋ 任意の穴 ([holes]) に戻した。分裂は 1 ドキュメントに
/// 複数リングを持たせるのではなく、独立したドキュメント群として表現する
/// （firestore_sync_service 参照）。
///   - [vertices]   単一の外周リング（CCW 目安）。
///   - [holes]      穴（A ⊂ B のケース。無ければ空）。
///   - [status]     'active'（実質これのみ。消滅は物理削除で表現）。
///   - [confirmed]  false の間は準備中（ピン2枚以下）で共有対象外。
class WalkPolygon {
  final String id;
  final String ownerUid;
  final String ownerName;

  /// colorPalette24 のインデックス
  final int colorId;

  /// 単一の外周リング
  final List<LatLng> vertices;

  /// 穴（任意）
  final List<List<LatLng>> holes;

  /// 多角形が「確定した」時刻。準備中は null。
  final DateTime? createdAt;

  /// オーナが最後にこの領域を「主張」した時刻（新規作成 or 頂点追加）。
  ///
  /// ★ 塗り合いの上下関係（どちらの色が上に塗られるか）と減算方向は、この
  ///   [claimedAt] の新しさで決まる。相手に領域を奪われても（減算されても）
  ///   [claimedAt] は変化しない。これにより、後から頂点を追加した側が相手の
  ///   領域を塗り返す、という往復が何回でも成立する。
  ///   旧データ（claimedAt 無し）は [createdAt] にフォールバックする。
  final DateTime? claimedAt;

  /// 最後に減算（領域を奪われた）された時刻。
  final DateTime? lastModifiedAt;

  /// 直近の減算を行った A の polygonId（履歴用）。
  final String? subtractedBy;

  /// 構成する写真ピンの ID リスト
  final List<String> photoIds;

  /// 3点以上集まり領域として確定済みか
  final bool confirmed;

  /// 'active'（実質これのみ）
  final String status;

  const WalkPolygon({
    required this.id,
    required this.ownerUid,
    required this.ownerName,
    required this.colorId,
    required this.vertices,
    this.holes = const [],
    required this.createdAt,
    required this.photoIds,
    required this.confirmed,
    this.claimedAt,
    this.lastModifiedAt,
    this.subtractedBy,
    this.status = 'active',
  });

  int get vertexCount => vertices.length;
  bool get isActive => status == 'active';

  /// 塗り合いの順序判定に使う「主張時刻」。claimedAt が無ければ createdAt。
  DateTime? get claimStamp => claimedAt ?? createdAt;

  WalkPolygon copyWith({
    String? ownerUid,
    String? ownerName,
    int? colorId,
    List<LatLng>? vertices,
    List<List<LatLng>>? holes,
    DateTime? createdAt,
    DateTime? claimedAt,
    DateTime? lastModifiedAt,
    String? subtractedBy,
    List<String>? photoIds,
    bool? confirmed,
    String? status,
  }) {
    return WalkPolygon(
      id: id,
      ownerUid: ownerUid ?? this.ownerUid,
      ownerName: ownerName ?? this.ownerName,
      colorId: colorId ?? this.colorId,
      vertices: vertices ?? this.vertices,
      holes: holes ?? this.holes,
      createdAt: createdAt ?? this.createdAt,
      claimedAt: claimedAt ?? this.claimedAt,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      subtractedBy: subtractedBy ?? this.subtractedBy,
      photoIds: photoIds ?? this.photoIds,
      confirmed: confirmed ?? this.confirmed,
      status: status ?? this.status,
    );
  }

  // ── シリアライズ ──────────────────────────────

  static Map<String, dynamic> _ll(LatLng v) =>
      {'lat': v.latitude, 'lng': v.longitude};

  static LatLng _toLL(dynamic e) {
    final m = e as Map<String, dynamic>;
    return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
  }

  static List<LatLng> _parsePoints(dynamic r) {
    if (r is Map) {
      return (r['points'] as List<dynamic>? ?? []).map(_toLL).toList();
    }
    return (r as List<dynamic>).map(_toLL).toList();
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'ownerUid': ownerUid,
        'ownerName': ownerName,
        'colorId': colorId,
        'vertices': vertices.map(_ll).toList(),
        // Firestore は配列の直下に配列を置けないため、穴は map で包む。
        'holes': holes.map((h) => {'points': h.map(_ll).toList()}).toList(),
        'createdAt': createdAt?.millisecondsSinceEpoch,
        // 主張時刻。旧データ互換のため未設定なら createdAt を書き込む。
        'claimedAt': (claimedAt ?? createdAt)?.millisecondsSinceEpoch,
        'lastModifiedAt': lastModifiedAt?.millisecondsSinceEpoch,
        'subtractedBy': subtractedBy,
        'photoIds': photoIds,
        'confirmed': confirmed,
        'status': status,
      };

  factory WalkPolygon.fromMap(Map<String, dynamic> map) {
    // 外周リング
    List<LatLng> vertices;
    if (map['vertices'] != null) {
      vertices = (map['vertices'] as List<dynamic>).map(_toLL).toList();
    } else if (map['rings'] != null) {
      // v3 旧形式との後方互換
      final rings = (map['rings'] as List<dynamic>);
      if (rings.length >= 2) {
        // 実運用データが無い前提。マイグレーションは非対応。
        throw StateError('v3 の複数リング多角形は非対応です（要マイグレーション）');
      }
      vertices = rings.isEmpty ? <LatLng>[] : _parsePoints(rings.first);
    } else {
      vertices = <LatLng>[];
    }

    // 穴
    List<List<LatLng>> holes;
    if (map['holes'] != null) {
      holes = (map['holes'] as List<dynamic>).map((h) {
        // 新形式 {'points':[...]} / 旧形式 [...] / v3 {'rings':[...]}
        if (h is Map && h['points'] != null) return _parsePoints(h);
        if (h is Map && h['rings'] != null) {
          final inner = (h['rings'] as List<dynamic>);
          return inner.isEmpty ? <LatLng>[] : _parsePoints(inner.first);
        }
        return _parsePoints(h);
      }).toList();
    } else {
      holes = const [];
    }

    final createdMs = map['createdAt'];
    final claimedMs = map['claimedAt'];
    final modMs = map['lastModifiedAt'];
    return WalkPolygon(
      id: map['id'] as String,
      ownerUid: map['ownerUid'] as String? ?? '',
      ownerName: map['ownerName'] as String? ?? '名無し',
      colorId: (map['colorId'] as num?)?.toInt() ?? 0,
      vertices: vertices,
      holes: holes,
      createdAt: createdMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((createdMs as num).toInt()),
      claimedAt: claimedMs == null
          ? (createdMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch((createdMs as num).toInt()))
          : DateTime.fromMillisecondsSinceEpoch((claimedMs as num).toInt()),
      lastModifiedAt: modMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((modMs as num).toInt()),
      subtractedBy: map['subtractedBy'] as String?,
      photoIds: (map['photoIds'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
      confirmed: map['confirmed'] as bool? ?? true,
      status: map['status'] as String? ?? 'active',
    );
  }
}
