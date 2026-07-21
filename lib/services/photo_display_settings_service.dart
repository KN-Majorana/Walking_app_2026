import 'package:shared_preferences/shared_preferences.dart';

/// マップモードの写真表示に関する設定を永続化するサービス。
///
/// 「歴代の対戦の軌跡から霧を晴らすか」の設定は廃止した（常時オン）。
/// 現在は「対戦中に撮った写真をマップモードの地図へピン表示するか」だけを持つ。
class PhotoDisplaySettingsService {
  PhotoDisplaySettingsService._();

  static const _keyShowBattlePhotoPins = 'show_battle_photo_pins';

  /// 対戦写真をマップモードの地図にピン表示するか（デフォルト true）。
  static Future<bool> loadShowBattlePhotoPins() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowBattlePhotoPins) ?? true;
  }

  static Future<void> saveShowBattlePhotoPins(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowBattlePhotoPins, value);
  }
}
