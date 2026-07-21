import 'dart:convert';
import 'dart:io';

import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../color_extraction.dart';
import '../photo_pin.dart';
import 'app_paths.dart';

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
  static const _trajectoryFileName = 'battle_trajectory_history.json';

  static Future<File> _file() async {
    await AppPaths.ensureInitialized();
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<File> _trajectoryFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_trajectoryFileName');
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
          'imagePath': AppPaths.toStorable(e.imagePath),
          'latitude': e.lat,
          'longitude': e.lng,
          'takenAt': e.takenAt.toIso8601String(),
        };
      }
      final file = await _file();
      await file.writeAsString(jsonEncode(byId.values.toList()));
    } catch (_) {}
  }

  /// 抽出済みの主要色（24色パレットのインデックス）を履歴へ書き戻す。
  ///
  /// 対戦モードは専用パレットで色判定するため、フォトモードで使う 24 色の
  /// 色情報は履歴に入っていない。マップ側で一度だけ抽出し、ここへ保存して
  /// 次回以降の再計算を避ける。
  static Future<void> saveColorIds(Map<String, List<int>> colorIdsById) async {
    if (colorIdsById.isEmpty) return;
    try {
      final existing = await loadAll();
      final updated = existing.map((p) {
        final ids = colorIdsById[p.id];
        if (ids == null) return p;
        return PhotoPin(
          id: p.id,
          imagePath: p.imagePath,
          position: p.position,
          takenAt: p.takenAt,
          colorIds: ids,
          capturedMode: 'battle',
        );
      }).toList();
      final file = await _file();
      await file.writeAsString(jsonEncode(updated.map(_toJson).toList()));
    } catch (_) {}
  }

  /// 指定 id の歴代対戦写真を履歴から削除する（写真一覧の削除操作用）。
  /// 実ファイルも併せて削除する。
  static Future<void> deleteByIds(Set<String> ids) async {
    if (ids.isEmpty) return;
    try {
      final existing = await loadAll();
      final remaining = <PhotoPin>[];
      for (final p in existing) {
        if (!ids.contains(p.id)) {
          remaining.add(p);
          continue;
        }
        try {
          final f = File(p.imagePath);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      final file = await _file();
      await file.writeAsString(
        jsonEncode(remaining.map(_toJson).toList()),
      );
    } catch (_) {}
  }

  // ─────────────────────────────────────────
  // 対戦中の移動軌跡（位置情報の軌跡）
  // ─────────────────────────────────────────

  /// 歴代の対戦中の移動軌跡（座標列）を読み込む。
  static Future<List<LatLng>> loadTrajectory() async {
    try {
      final file = await _trajectoryFile();
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

  /// 対戦中の移動軌跡を追記する。近すぎる点は間引く（約8m）。
  static Future<void> appendTrajectory(List<LatLng> points) async {
    if (points.isEmpty) return;
    try {
      final existing = await loadTrajectory();
      final merged = <LatLng>[...existing];
      const distance = Distance(roundResult: false);
      for (final p in points) {
        if (merged.isEmpty || distance(merged.last, p) > 8) {
          merged.add(p);
        }
      }
      final file = await _trajectoryFile();
      await file.writeAsString(
        jsonEncode(
          merged.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
        ),
      );
    } catch (_) {}
  }

  /// マップモードの霧晴らしに使う「歴代の対戦の通過点」。
  ///
  /// 霧が晴れるのは「実際に歩いて通った場所」だけという方針のため、
  /// 対戦中の移動軌跡のみを返す。写真の撮影位置は霧を晴らさない
  /// （どのモードで撮った写真でも同じ扱い）。
  static Future<List<LatLng>> loadFogPoints() async {
    return loadTrajectory();
  }

  static Future<void> clearAll() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
      final tfile = await _trajectoryFile();
      if (await tfile.exists()) await tfile.delete();
    } catch (_) {}
  }

  static Map<String, dynamic> _toJson(PhotoPin p) => {
        'id': p.id,
        'imagePath': AppPaths.toStorable(p.imagePath),
        'latitude': p.position.latitude,
        'longitude': p.position.longitude,
        'takenAt': p.takenAt.toIso8601String(),
        // フォトモード（24色パレット）でのグループ化に使う主要色。
        // 対戦モードの色（colorPaletteBattle）とは別物なので、
        // マップ側で抽出した結果をここへ保存する。
        'colorNames': p.colorIds
            .where((i) => i >= 0 && i < colorNames24.length)
            .map((i) => colorNames24[i])
            .toList(),
      };

  static PhotoPin? _fromJson(Map<String, dynamic> json) {
    try {
      return PhotoPin(
        id: json['id'] as String?,
        imagePath: AppPaths.toAbsolute(json['imagePath'] as String),
        position: LatLng(
          (json['latitude'] as num).toDouble(),
          (json['longitude'] as num).toDouble(),
        ),
        takenAt: DateTime.parse(json['takenAt'] as String),
        colorIds: ((json['colorNames'] as List<dynamic>?) ?? const [])
            .map((e) => colorNames24.indexOf(e as String))
            .where((i) => i >= 0)
            .toList(),
        capturedMode: 'battle',
      );
    } catch (_) {
      return null;
    }
  }
}
