import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/completed_collage.dart';

/// 完成済みコラージュの一覧を JSON ファイルに永続化するサービス
class CompletedCollageStorageService {
  CompletedCollageStorageService._();

  static const _fileName = 'completed_collages.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// 完成済みコラージュの画像を保存するディレクトリ（なければ作成）
  static Future<Directory> imagesDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${dir.path}/collages');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir;
  }

  /// 保存済みの完成コラージュをすべて読み込む
  static Future<List<CompletedCollage>> loadAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final text = await file.readAsString();
      if (text.isEmpty) return [];
      final list = jsonDecode(text) as List<dynamic>;
      return list
          .map((j) => CompletedCollage.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 1件の完成コラージュを追記保存する
  /// （同じ領域＝色が同じかつピンが重なるものが既にあれば上書き）
  static Future<void> save(CompletedCollage collage) async {
    final existing = await loadAll();
    final idx = existing.indexWhere(
      (c) => _isSameRegion(c, collage.colorId, collage.pinIds),
    );
    if (idx >= 0) {
      existing[idx] = collage;
    } else {
      existing.add(collage);
    }
    final file = await _file();
    await file.writeAsString(
      jsonEncode(existing.map((c) => c.toJson()).toList()),
    );
  }

  /// 指定した色・ピン集合と同じ領域の完成コラージュを探す。
  /// 「同じ領域」＝ 色が同じ かつ ピンが 1 つでも重なっている。
  static Future<CompletedCollage?> findForRegion(
    int colorId,
    List<String> pinIds,
  ) async {
    final all = await loadAll();
    for (final c in all) {
      if (_isSameRegion(c, colorId, pinIds)) return c;
    }
    return null;
  }

  static bool _isSameRegion(
    CompletedCollage existing,
    int colorId,
    List<String> pinIds,
  ) {
    if (existing.colorId != colorId) return false;
    final existingIds = existing.pinIds.toSet();
    return pinIds.any(existingIds.contains);
  }

  /// 指定した id の完成コラージュを 1 件削除する（画像ファイルも削除）
  static Future<void> delete(String id) async {
    await deleteMany({id});
  }

  /// 指定した id 群の完成コラージュをまとめて削除する（画像ファイルも削除）
  static Future<void> deleteMany(Set<String> ids) async {
    if (ids.isEmpty) return;
    final existing = await loadAll();
    final toRemove = existing.where((c) => ids.contains(c.id)).toList();
    if (toRemove.isEmpty) return;

    for (final c in toRemove) {
      try {
        final imgFile = File(c.imagePath);
        if (await imgFile.exists()) await imgFile.delete();
      } catch (_) {
        // 画像ファイルの削除に失敗しても、一覧からは除去を続行する
      }
    }

    final remaining = existing.where((c) => !ids.contains(c.id)).toList();
    final file = await _file();
    await file.writeAsString(
      jsonEncode(remaining.map((c) => c.toJson()).toList()),
    );
  }
}
