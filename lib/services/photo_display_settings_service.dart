import 'package:shared_preferences/shared_preferences.dart';

/// マップモードの霧晴らしに関する表示設定を永続化するサービス。
///
/// [loadUseBattleFog] が true の場合、マップモードでは「歴代の対戦」で通った
/// 場所（対戦中の移動軌跡＋対戦写真の撮影位置）からも霧を晴らす。
/// この機能はマップモード限定（コラージュモードには表示しない）。
class PhotoDisplaySettingsService {
  PhotoDisplaySettingsService._();

  static const _keyUseBattleFog = 'use_battle_history_fog';

  /// 歴代の対戦の軌跡・写真から霧を晴らすか（デフォルト true）。
  static Future<bool> loadUseBattleFog() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyUseBattleFog) ?? true;
  }

  static Future<void> saveUseBattleFog(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseBattleFog, value);
  }
}
