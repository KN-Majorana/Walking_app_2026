import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'walk_track.dart';

/// [WalkTrack]を端末に永続保存するサービス。
///
/// shared_preferencesに、各軌跡をJSON文字列化した配列として保持する。
/// キーは [_key]。同じidの軌跡は上書き保存する。
class TrackStorageService {
  TrackStorageService._();

  static const String _key = 'walks';

  /// 軌跡を保存する。同じidが既にあれば上書き、なければ末尾に追加。
  static Future<void> save(WalkTrack track) async {
    final prefs = await SharedPreferences.getInstance();
    final all = _readAll(prefs);
    final idx = all.indexWhere((t) => t.id == track.id);
    if (idx >= 0) {
      all[idx] = track;
    } else {
      all.add(track);
    }
    await _writeAll(prefs, all);
  }

  /// 保存済みの全軌跡を読み込む。壊れたデータは無視する。
  static Future<List<WalkTrack>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    return _readAll(prefs);
  }

  /// 指定idの軌跡を削除する。存在しなければ何もしない。
  static Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final all = _readAll(prefs);
    all.removeWhere((t) => t.id == id);
    await _writeAll(prefs, all);
  }

  /// 指定idの軌跡を1件取得する。無ければnull。
  static Future<WalkTrack?> loadById(String id) async {
    final all = await loadAll();
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  static List<WalkTrack> _readAll(SharedPreferences prefs) {
    final raw = prefs.getStringList(_key) ?? const <String>[];
    final result = <WalkTrack>[];
    for (final s in raw) {
      try {
        final json = jsonDecode(s) as Map<String, dynamic>;
        result.add(WalkTrack.fromJson(json));
      } catch (_) {
        // 壊れたエントリは黙ってスキップ。
      }
    }
    return result;
  }

  static Future<void> _writeAll(
    SharedPreferences prefs,
    List<WalkTrack> tracks,
  ) async {
    final raw = tracks.map((t) => jsonEncode(t.toJson())).toList();
    await prefs.setStringList(_key, raw);
  }
}
