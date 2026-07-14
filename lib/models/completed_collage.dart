import '../color_extraction.dart';

/// 完成させた（確定済みの）色ハンティングコラージュ 1件分のデータ。
///
/// 完成ボタンが押された時点の合成画像をファイルとして保存し、
/// そのファイルパスと対象の領域（写真ピンの集合）を記録する。
/// 完成の判定は「色」ではなく「領域（ピンの集合）」単位で行う。
/// 完成後はその領域のコラージュは編集できない。
class CompletedCollage {
  final String id;

  /// colorPalette24 のインデックス（表示用。実行時に使用）
  final int colorId;

  /// この領域（クラスタ）を構成する写真ピンの id 一覧。
  /// これが「領域」の識別子として使われる。
  final List<String> pinIds;

  /// 完成時に書き出した合成画像（PNG）のファイルパス
  final String imagePath;

  final DateTime createdAt;

  CompletedCollage({
    String? id,
    required this.colorId,
    required this.pinIds,
    required this.imagePath,
    required this.createdAt,
  }) : id = id ?? '${createdAt.microsecondsSinceEpoch}';

  /// JSON 保存: colorId ではなく色名（文字列）で保存
  /// → パレットの並び順が変わっても壊れない
  Map<String, dynamic> toJson() => {
    'id': id,
    'colorName': (colorId >= 0 && colorId < colorNames24.length)
        ? colorNames24[colorId]
        : null,
    'pinIds': pinIds,
    'imagePath': imagePath,
    'createdAt': createdAt.toIso8601String(),
  };

  factory CompletedCollage.fromJson(Map<String, dynamic> json) {
    final name = json['colorName'] as String?;
    final colorId = name != null ? colorNames24.indexOf(name) : -1;
    return CompletedCollage(
      id: json['id'] as String? ?? '${DateTime.now().microsecondsSinceEpoch}',
      colorId: colorId,
      pinIds: (json['pinIds'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
      imagePath: json['imagePath'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
