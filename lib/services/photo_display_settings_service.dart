import 'package:shared_preferences/shared_preferences.dart';

/// 地図上に表示する写真ピンの表示設定を永続化するサービス。
///
/// デフォルトでは「マップ」「コラージュ」モードで撮影した写真のみを表示する。
/// [loadShowBattlePhotos] が true の場合、対戦モードで撮影した歴代の写真も表示する。
class PhotoDisplaySettingsService {
  PhotoDisplaySettingsService._();

  static const _keyShowBattlePhotos = 'show_battle_photos';

  /// 対戦モードの歴代写真を表示するかどうか（デフォルト false）。
  static Future<bool> loadShowBattlePhotos() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowBattlePhotos) ?? false;
  }

  static Future<void> saveShowBattlePhotos(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowBattlePhotos, value);
  }
}
