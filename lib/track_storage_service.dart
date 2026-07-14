import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'walk_track.dart';

/// 散歩記録をJSONファイルに永続化するサービス
class TrackStorageService {
  TrackStorageService._();

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'walk_tracks.json'));
  }

  /// 保存済みの全軌跡を読み込む
  static Future<List<WalkTrack>> loadAll() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return [];
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => WalkTrack.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 1件の軌跡を追記保存する
  static Future<void> save(WalkTrack track) async {
    final existing = await loadAll();
    // 同じIDがあれば上書き、なければ追加
    final idx = existing.indexWhere((t) => t.id == track.id);
    if (idx >= 0) {
      existing[idx] = track;
    } else {
      existing.add(track);
    }
    final file = await _file();
    await file.writeAsString(jsonEncode(existing.map((t) => t.toJson()).toList()));
  }

  /// 指定した id の軌跡を削除する
  static Future<void> delete(String id) async {
    final existing = await loadAll();
    existing.removeWhere((t) => t.id == id);
    final file = await _file();
    await file.writeAsString(jsonEncode(existing.map((t) => t.toJson()).toList()));
  }
}
