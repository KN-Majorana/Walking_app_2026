import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// 対戦モード用のカメラ撮影・ギャラリー取得・保存サービス。
///
/// 写真は battle スコープの専用ディレクトリに保存される：
///   ApplicationDocumentsDirectory/battles/{battleId}/photos/
///
/// この分離により、`FirestoreSyncService.purgeBattleLocal(battleId)` を
/// 呼ぶだけで対戦単位のローカル写真を一括削除できる。
class PhotoService {
  PhotoService._();

  static final _picker = ImagePicker();

  static Future<Directory> _dirForBattle(String battleId) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/battles/$battleId/photos');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// カメラで撮影し、battle 用ディレクトリに保存する。
  static Future<String?> takeAndSavePhotoForBattle(String battleId) async {
    final xFile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (xFile == null) return null;

    final dir = await _dirForBattle(battleId);
    final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final destPath = p.join(dir.path, fileName);
    await File(xFile.path).copy(destPath);
    return destPath;
  }

  /// ギャラリーから 1 枚選び、battle 用ディレクトリに保存する。
  /// EXIF を保つため imageQuality は指定しない。
  static Future<String?> pickFromGalleryAndSaveForBattle(String battleId) async {
    final xFile = await _picker.pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: true,
    );
    if (xFile == null) return null;

    final dir = await _dirForBattle(battleId);
    final ext =
        p.extension(xFile.path).isNotEmpty ? p.extension(xFile.path) : '.jpg';
    final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}$ext';
    final destPath = p.join(dir.path, fileName);
    await File(xFile.path).copy(destPath);
    return destPath;
  }

  /// 【デモ】アセット画像（assets/demo_photos/*.png）を battle 用ディレクトリへ
  /// 実ファイルとして書き出し、そのパスを返す。実カメラで撮影した写真の代わりに
  /// 使う（以降の処理は通常の撮影写真と全く同じパイプラインを通る）。
  static Future<String?> saveAssetAsBattlePhoto(
      String battleId, String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      final dir = await _dirForBattle(battleId);
      final ext = p.extension(assetPath).isNotEmpty
          ? p.extension(assetPath)
          : '.png';
      final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}$ext';
      final destPath = p.join(dir.path, fileName);
      await File(destPath).writeAsBytes(bytes, flush: true);
      return destPath;
    } catch (_) {
      return null;
    }
  }

  /// 色不一致などで捨てる写真ファイルを削除する。
  /// battle cleared 時の一括削除とは分離した用途で使う。
  static Future<void> deletePhotoFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
