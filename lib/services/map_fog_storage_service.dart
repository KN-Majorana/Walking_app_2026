import 'dart:convert';
import 'dart:io';

import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

/// 「マップ」モードで歩いて霧を晴らした地点（軌跡点）を永続化するサービス。
///
/// コラージュモードの色クラスタとは無関係で、単純に「これまでに通過した座標」を
/// 保存する。再起動後も晴れた場所が残るよう、アプリ内に JSON で保持する。
class MapFogStorageService {
  MapFogStorageService._();

  static const _fileName = 'map_fog_cleared_points.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// 晴らした地点をすべて読み込む。
  static Future<List<LatLng>> loadAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final text = await file.readAsString();
      if (text.isEmpty) return [];
      final list = jsonDecode(text) as List<dynamic>;
      return list
          .map((j) => LatLng(
                (j['lat'] as num).toDouble(),
                (j['lng'] as num).toDouble(),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 晴らした地点をすべて保存する（上書き）。
  static Future<void> saveAll(List<LatLng> points) async {
    try {
      final file = await _file();
      final json = jsonEncode(
        points
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
      );
      await file.writeAsString(json);
    } catch (_) {}
  }

  /// すべての晴らし履歴を消す。
  static Future<void> clearAll() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
