import 'package:latlong2/latlong.dart';

import 'color_extraction.dart';

/// 撮影した写真とその位置情報・主要色を保持するモデル
class PhotoPin {
  final String id;
  final String imagePath;
  final LatLng position;
  final DateTime takenAt;

  /// colorPalette24 のインデックスリスト（実行時に使用）
  final List<int> colorIds;

  /// 散歩の記録中（記録開始〜終了の間）に撮影されたものかどうか。
  /// 領域（色クラスタ）を作るアルゴリズムはこれが true のピンのみを対象にする。
  final bool capturedDuringWalk;

  PhotoPin({
    String? id,
    required this.imagePath,
    required this.position,
    required this.takenAt,
    this.colorIds = const [],
    this.capturedDuringWalk = false,
  }) : id = id ?? '${takenAt.microsecondsSinceEpoch}';

  /// JSON 保存: colorIds をインデックスではなく色名（文字列）で保存
  /// → パレットの並び順が変わっても壊れない
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
    'capturedDuringWalk': capturedDuringWalk,
  };

  factory PhotoPin.fromJson(Map<String, dynamic> json) {
    // 新形式（colorNames）を優先、旧形式（colorIds）にも対応
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
      // 旧インデックス形式: 範囲外は除去
      ids = (json['colorIds'] as List<dynamic>? ?? [])
          .map((e) => (e as num).toInt())
          .where((i) => i >= 0 && i < colorPalette24.length)
          .toList();
    }

    return PhotoPin(
      id: json['id'] as String? ?? '${DateTime.now().microsecondsSinceEpoch}',
      imagePath: json['imagePath'] as String,
      position: LatLng(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      ),
      takenAt: DateTime.parse(json['takenAt'] as String),
      colorIds: ids,
      // 旧データ（記録済み: フラグなし）は false 扱い＝領域作成の対象外とする
      capturedDuringWalk: json['capturedDuringWalk'] as bool? ?? false,
    );
  }
}
