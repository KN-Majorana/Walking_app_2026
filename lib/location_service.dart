import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  /// 現在地を1回だけ取得する
  static Future<LatLng> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('位置情報サービスが無効です');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('位置情報の権限が拒否されました');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('位置情報の権限が永久に拒否されています');
    }

    final position = await Geolocator.getCurrentPosition();
    return LatLng(position.latitude, position.longitude);
  }

  /// バックグラウンド（他アプリ使用中・画面ロック中）でも位置取得を続けるために
  /// 「常に許可」を要求する。
  ///
  /// Android 10+ では「使用中のみ許可」を先に取ってから、
  /// 別ダイアログで「常に許可」を求める必要がある（2段階リクエスト）。
  /// すでに「常に許可」が下りていれば何もしない。
  ///
  /// 戻り値: 常に許可が得られたら true、そうでなければ false。
  static Future<bool> requestBackgroundPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();

    // まず「使用中のみ許可」を取る
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    // すでに「常に許可」ならOK
    if (permission == LocationPermission.always) {
      return true;
    }

    // 「使用中のみ許可」の状態から「常に許可」を追加で要求する。
    // Androidではこの呼び出しで設定画面に遷移するケースがある。
    if (permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always;
  }

  /// 現在の権限が「常に許可」かどうかを確認する（リクエストはしない）
  static Future<bool> hasBackgroundPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always;
  }

  /// 現在地を継続的に取得するStream(記録モード用)
  /// [distanceFilter] メートル単位。指定距離移動するごとに値が流れる
  ///
  /// バックグラウンドでも継続させたい場合は、Androidでは
  /// [AndroidSettings.foregroundNotificationConfig] を設定することで、
  /// 通知を出しながらフォアグラウンドサービスとして位置取得を継続できる。
  static Stream<LatLng> watchPosition({int distanceFilter = 5}) {
    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
      // バックグラウンドでもストリームを止めない
      forceLocationManager: false,
      intervalDuration: const Duration(seconds: 5),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationText: '散歩を記録中です',
        notificationTitle: '位置情報を取得しています',
        enableWakeLock: true,
        notificationIcon: AndroidResource(
          name: 'ic_launcher',
          defType: 'mipmap',
        ),
      ),
    );

    return Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).map((p) => LatLng(p.latitude, p.longitude));
  }
}
