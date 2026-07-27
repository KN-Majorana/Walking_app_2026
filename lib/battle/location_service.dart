import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// GPS位置情報を取得・監視するサービス。
///
/// 対戦モードではバックグラウンドでも位置を取得し続けたいので、
/// プラットフォームごとに背景取得を有効化した [LocationSettings] を使う。
///   * Android: フォアグラウンドサービス通知を出して背景取得を継続する。
///   * iOS    : allowBackgroundLocationUpdates を有効化する
///              （Info.plist の UIBackgroundModes=location が必要）。
class LocationService {
  LocationService._();

  static const int _distanceFilterMeters = 5;

  /// プラットフォーム別の位置設定を構築する。
  static LocationSettings _buildSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilterMeters,
        // 背景でも取得を継続するためのフォアグラウンドサービス通知。
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: '対戦中',
          notificationText: '現在地を取得しています',
          enableWakeLock: true,
        ),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilterMeters,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
        activityType: ActivityType.fitness,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: _distanceFilterMeters,
    );
  }

  /// 現在地を1回取得する。
  static Future<LatLng> getCurrentPosition() async {
    await _ensurePermission();
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: _buildSettings(),
    );
    return LatLng(pos.latitude, pos.longitude);
  }

  /// 位置情報の継続ストリームを返す（背景取得対応）。
  static Stream<LatLng> watchPosition() async* {
    await _ensurePermission();
    yield* Geolocator.getPositionStream(
      locationSettings: _buildSettings(),
    ).map((pos) => LatLng(pos.latitude, pos.longitude));
  }

  /// 位置情報の権限を確保する。
  /// フォアグラウンド許可を得たあと、可能であれば「常に許可」への昇格も試みる
  /// （背景取得のため。ユーザが拒否しても前面取得は継続できる）。
  static Future<void> _ensurePermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      throw Exception('位置情報のアクセスが永続的に拒否されています');
    }
    // whileInUse を得たら、背景取得のため always への昇格を1度だけ促す。
    if (perm == LocationPermission.whileInUse) {
      try {
        await Geolocator.requestPermission();
      } catch (_) {}
    }
  }
}
