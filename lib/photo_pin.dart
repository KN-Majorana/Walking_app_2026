import 'package:latlong2/latlong.dart';

import 'color_extraction.dart';

/// 撮影した写真とその位置情報・主要色を保持するモデル。
///
/// v6-9 で対戦モードの「3 状態モデル」に対応した：
///   * pending   : `polygonId == null && !isDetached`（同色 3 枚未達）
///   * attached  : `polygonId != null && !isDetached`（多角形の正式頂点）
///   * detached  : `polygonId == null &&  isDetached`（切り離された終端状態）
///
/// detached からの復帰は無い。battle が cleared になるまで detached を保持する。
class PhotoPin {
  final String id;

  /// 端末ローカルの画像パス
  final String imagePath;

  final LatLng position;
  final DateTime takenAt;

  /// colorPalette24 のインデックスリスト（画像判定色）
  final List<int> colorIds;

  /// 所有者の Firebase UID
  final String? ownerUid;

  /// 属する多角形の ID。pending / detached では null。
  final String? polygonId;

  /// 端末にローカル画像実体が存在するか（他端末では常に false）。
  final bool hasImageOnDevice;

  /// 表示専用の孤立ピンかどうか（true = detached）。
  final bool isDetached;

  /// detached になった時刻（isDetached==true のときのみ有効）。
  final DateTime? detachedAt;

  PhotoPin({
    String? id,
    required this.imagePath,
    required this.position,
    required this.takenAt,
    this.colorIds = const [],
    this.ownerUid,
    this.polygonId,
    this.hasImageOnDevice = true,
    this.isDetached = false,
    this.detachedAt,
  }) : id = id ?? '${takenAt.microsecondsSinceEpoch}';

  /// pending 状態か（3 枚判定・新規作成の候補集合の判定に使う）。
  bool get isPending => polygonId == null && !isDetached;

  /// attached 状態か（既存多角形の頂点候補・実効面積に寄与する状態）。
  bool get isAttached => polygonId != null && !isDetached;

  PhotoPin copyWith({
    String? imagePath,
    LatLng? position,
    DateTime? takenAt,
    List<int>? colorIds,
    String? ownerUid,
    // polygonId は null 化を許可するため Object? センチネル方式にする
    Object? polygonId = _kSentinel,
    bool? hasImageOnDevice,
    bool? isDetached,
    Object? detachedAt = _kSentinel,
  }) {
    return PhotoPin(
      id: id,
      imagePath: imagePath ?? this.imagePath,
      position: position ?? this.position,
      takenAt: takenAt ?? this.takenAt,
      colorIds: colorIds ?? this.colorIds,
      ownerUid: ownerUid ?? this.ownerUid,
      polygonId: identical(polygonId, _kSentinel)
          ? this.polygonId
          : polygonId as String?,
      hasImageOnDevice: hasImageOnDevice ?? this.hasImageOnDevice,
      isDetached: isDetached ?? this.isDetached,
      detachedAt: identical(detachedAt, _kSentinel)
          ? this.detachedAt
          : detachedAt as DateTime?,
    );
  }

  /// JSON 保存
  Map<String, dynamic> toJson() => {
        'id': id,
        'imagePath': imagePath,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'takenAt': takenAt.toIso8601String(),
        'colorNames': colorIds
            .where((i) => i >= 0 && i < colorNames24.length)
            .map((i) => colorNames24[i])
            .toList(),
        // 旧データとの互換のため null 値のキーは省略
        if (ownerUid != null) 'ownerUid': ownerUid,
        if (polygonId != null) 'polygonId': polygonId,
        'hasImageOnDevice': hasImageOnDevice,
        if (isDetached) 'isDetached': true,
        if (detachedAt != null) 'detachedAt': detachedAt!.toIso8601String(),
      };

  factory PhotoPin.fromJson(Map<String, dynamic> json) {
    List<int> ids;
    if (json.containsKey('colorNames')) {
      final names = (json['colorNames'] as List<dynamic>)
          .map((e) => e as String)
          .toList();
      ids = names
          .map((name) => colorNames24.indexOf(name))
          .where((i) => i >= 0)
          .toList();
    } else {
      ids = (json['colorIds'] as List<dynamic>? ?? [])
          .map((e) => (e as num).toInt())
          .where((i) => i >= 0 && i < colorPalette24.length)
          .toList();
    }

    return PhotoPin(
      id: json['id'] as String? ?? '${DateTime.now().microsecondsSinceEpoch}',
      imagePath: json['imagePath'] as String? ?? '',
      position: LatLng(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      ),
      takenAt: DateTime.parse(json['takenAt'] as String),
      colorIds: ids,
      ownerUid: json['ownerUid'] as String?,
      polygonId: json['polygonId'] as String?,
      // 旧データには存在しないキー → デフォルトへフォールバック
      hasImageOnDevice: json['hasImageOnDevice'] as bool? ?? true,
      isDetached: json['isDetached'] as bool? ?? false,
      detachedAt: json['detachedAt'] == null
          ? null
          : DateTime.tryParse(json['detachedAt'] as String),
    );
  }

  // ─────────────────────────────────────────
  // Firestore 用（battles/{battleId}/photos/{photoId}）
  // ─────────────────────────────────────────

  Map<String, dynamic> toFirestoreMap() => {
        'id': id,
        'ownerUid': ownerUid,
        'polygonId': polygonId,
        'lat': position.latitude,
        'lng': position.longitude,
        'takenAt': takenAt.millisecondsSinceEpoch,
        // colorIds の 1 個目を主要色として保存（対戦は 1 色固定）
        'colorId': colorIds.isNotEmpty ? colorIds.first : -1,
        'isDetached': isDetached,
        if (detachedAt != null)
          'detachedAt': detachedAt!.millisecondsSinceEpoch,
      };

  /// Firestore ドキュメントから復元する（実画像は他端末上にないので
  /// [hasImageOnDevice]=false, [imagePath]=空 で復元される）。
  factory PhotoPin.fromFirestoreMap(Map<String, dynamic> map) {
    final colorId = (map['colorId'] as num?)?.toInt();
    return PhotoPin(
      id: map['id'] as String,
      imagePath: '',
      position: LatLng(
        (map['lat'] as num).toDouble(),
        (map['lng'] as num).toDouble(),
      ),
      takenAt: DateTime.fromMillisecondsSinceEpoch(
          (map['takenAt'] as num).toInt()),
      colorIds: colorId != null && colorId >= 0 ? [colorId] : const [],
      ownerUid: map['ownerUid'] as String?,
      polygonId: map['polygonId'] as String?,
      hasImageOnDevice: false,
      isDetached: map['isDetached'] as bool? ?? false,
      detachedAt: map['detachedAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (map['detachedAt'] as num).toInt()),
    );
  }
}

const Object _kSentinel = Object();
