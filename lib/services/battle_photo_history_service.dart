import 'dart:convert';
import 'dart:io';

import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../photo_pin.dart';

/// 対戦モードで撮影した写真の「歴代」履歴を永続化するサービス。
///
/// 対戦の実データ（battles/{id}/photos や Firestore ミラー）は対戦終了で
/// 消去され得るため、地図（マップ／コラージュ）モードで歴代写真を表示できるよう、
/// 対戦リザルト表示時に自分の写真をここへ蓄積する。
///
/// 保持する PhotoPin は capturedMode = 'battle' として復元される。
class BattlePhotoHistoryService {
  BattlePhotoHistoryService._();

  static const _fileName = 'battle_photo_history.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// 歴代の対戦写真をすべて読み込む（capturedMode = 'battle'）。
  static Future<List<PhotoPin>> loadAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final text = await file.readAsString();
      if (text.isEmpty) return [];
      final list = jsonDecode(text) as List<dynamic>;
      return list
          .map((j) => _fromJson(j as Map<String, dynamic>))
          .whereType<PhotoPin>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 与えられた写真を履歴へ追記する（id で重複排除）。
  /// ローカルに画像実体があり、位置情報を持つものだけを保存する。
  static Future<void> appendAll(Iterable<PhotoPin> pins) async {
    try {
      final existing = await loadAll();
      final byId = {for (final p in existing) p.id: p};
      for (final p in pins) {
        if (p.imagePath.isEmpty) continue;
        byId[p.id] = p;
      }
      final file = await _file();
      await file.writeAsString(
        jsonEncode(byId.values.map(_toJson).toList()),
      );
    } catch (_) {}
  }

  /// 対戦画面側（battle の PhotoPin 型）から呼ぶための、プリミティブ版の追記。
  /// 位置情報と画像パスを持つ写真だけを蓄積する（id で重複排除）。
  static Future<void> appendEntries(
    List<
            ({
              String id,
              String imagePath,
              double lat,
              double lng,
              DateTime takenAt
            })>
        entries,
  ) async {
    try {
      final existing = await loadAll();
      final byId = {for (final p in existing) p.id: _toJson(p)};
      for (final e in entries) {
        if (e.imagePath.isEmpty) continue;
        byId[e.id] = {
          'id': e.id,
          'imagePath': e.imagePath,
          'latitude': e.lat,
          'longitude': e.lng,
          'takenAt': e.takenAt.toIso8601String(),
        };
      }
      final file = await _file();
      await file.writeAsString(jsonEncode(byId.values.toList()));
    } catch (_) {}
  }

  static Future<void> clearAll() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Map<String, dynamic> _toJson(PhotoPin p) => {
        'id': p.id,
        'imagePath': p.imagePath,
        'latitude': p.position.latitude,
        'longitude': p.position.longitude,
        'takenAt': p.takenAt.toIso8601String(),
      };

  static PhotoPin? _fromJson(Map<String, dynamic> json) {
    try {
      return PhotoPin(
        id: json['id'] as String?,
        imagePath: json['imagePath'] as String,
        position: LatLng(
          (json['latitude'] as num).toDouble(),
          (json['longitude'] as num).toDouble(),
        ),
        takenAt: DateTime.parse(json['takenAt'] as String),
        capturedMode: 'battle',
      );
    } catch (_) {
      return null;
    }
  }
}
