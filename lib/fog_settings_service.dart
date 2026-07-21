import 'package:shared_preferences/shared_preferences.dart';

/// 霧オーバーレイの設定を永続化するサービス
class FogSettingsService {
  static const _keyMaxDistance = 'fog_max_distance_meters';

  /// デフォルトのピン間最大距離（メートル）
  static const double defaultMaxDistance = 1000.0;

  /// 保存されている最大距離を読み込む
  static Future<double> loadMaxDistance() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyMaxDistance) ?? defaultMaxDistance;
  }

  /// 最大距離を保存する
  static Future<void> saveMaxDistance(double meters) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyMaxDistance, meters);
  }
}
