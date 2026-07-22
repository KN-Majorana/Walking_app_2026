import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// GPS位置情報を取得・監視するサービス（散歩モード）。
///
/// 散歩の「記録中」は背景に回っても位置を取得し続けたいので、
/// [background] を true にするとプラットフォームごとに背景取得を
/// 有効化した [LocationSettings] を使う。
///   * Android: フォアグラウンドサービス通知を出して背景取得を継続する。
///              （FOREGROUND_SERVICE / FOREGROUND_SERVICE_LOCATION /
///                ACCESS_BACKGROUND_LOCATION の権限が必要）。
///   * iOS    : allowBackgroundLocationUpdates を有効化する
///              （Info.plist の UIBackgroundModes=location が必要）。
class LocationService {
  LocationService._();

  static const int _distanceFilterMeters = 5;

  /// プラットフォーム別の位置設定を構築する。
  /// [background] が true のときだけ背景取得を有効化する。
  static LocationSettings _buildSettings({required bool background}) {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilterMeters,
        // 背景でも取得を継続するためのフォアグラウンドサービス通知。
        // 記録中(background=true)のときだけ通知を出す。
        foregroundNotificationConfig: background
            ? const ForegroundNotificationConfig(
                notificationTitle: '散歩を記録中',
                notificationText: '現在地を取得しています',
                enableWakeLock: true,
              )
            : null,
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilterMeters,
        allowBackgroundLocationUpdates: background,
        showBackgroundLocationIndicator: background,
        pauseLocationUpdatesAutomatically: false,
        activityType: ActivityType.fitness,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: _distanceFilterMeters,
    );
  }

  /// 現在地を1回取得する
  static Future<LatLng> getCurrentPosition() async {
    await _ensurePermission();
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: _buildSettings(background: false),
    );
    return LatLng(pos.latitude, pos.longitude);
  }

  /// 位置情報の継続ストリームを返す。
  /// [background] が true のとき背景取得を有効化する。
  static Stream<LatLng> watchPosition({bool background = false}) async* {
    await _ensurePermission(requireAlways: background);
    await for (final pos in Geolocator.getPositionStream(
      locationSettings: _buildSettings(background: background),
    )) {
      yield LatLng(pos.latitude, pos.longitude);
    }
  }

  /// 速度など詳細を含む Position の継続ストリームを返す。
  /// 距離・速度の計測に使う（LatLng だけでは速度が取れないため）。
  /// [background] が true のとき背景取得を有効化する。
  static Stream<Position> watchPositionRaw({bool background = false}) async* {
    await _ensurePermission(requireAlways: background);
    yield* Geolocator.getPositionStream(
      locationSettings: _buildSettings(background: background),
    );
  }

  /// 位置情報の権限を確保する。
  /// [requireAlways] が true のときは、背景取得のため「常に許可」への
  /// 昇格も促す（ユーザが拒否しても前面取得は継続できる）。
  static Future<void> _ensurePermission({bool requireAlways = false}) async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      throw Exception('位置情報のアクセスが永続的に拒否されています');
    }
    // whileInUse を得たら、背景取得のため always への昇格を1度だけ促す。
    if (requireAlways && perm == LocationPermission.whileInUse) {
      try {
        await Geolocator.requestPermission();
      } catch (_) {}
    }
  }
}
