import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../photo_pin.dart';

/// 写真ピンを JSON ファイルに永続化するサービス
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
}
