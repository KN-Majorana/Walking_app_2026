import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../photo_pin.dart';

/// 対戦モードにおける写真ピンのローカルミラーを永続化する。
///
/// このミラーは「Firestore からの復元コスト削減」と「オフライン時の
/// 表示継続」のためのキャッシュに過ぎない。個別削除 API は撤去し、
/// battle cleared 時の一括削除は
/// `FirestoreSyncService.purgeBattleLocal(battleId)` と併せて
/// `saveAll(const [])` で潰す運用にする。
class PhotoPinStorageService {
  static const _fileName = 'photo_pins.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// 全ピンを保存する
  static Future<void> saveAll(List<PhotoPin> pins) async {
    final file = await _file();
    final json = jsonEncode(pins.map((p) => p.toJson()).toList());
    await file.writeAsString(json);
  }

  /// 保存済みのピンをすべて読み込む
  static Future<List<PhotoPin>> loadAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final text = await file.readAsString();
      if (text.isEmpty) return [];
      final list = jsonDecode(text) as List<dynamic>;
      return list
          .map((j) => PhotoPin.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// ローカルミラーを完全に消す（battle cleared のタイミングで呼ぶ）。
  static Future<void> clearAll() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
