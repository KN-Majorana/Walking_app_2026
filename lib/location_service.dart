import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// GPS位置情報を取得・監視するサービス
class LocationService {
  LocationService._();

  static const _settings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5,
  );

  /// 現在地を1回取得する
  static Future<LatLng> getCurrentPosition() async {
    await _ensurePermission();
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: _settings,
    );
    return LatLng(pos.latitude, pos.longitude);
  }

  /// 位置情報の継続ストリームを返す
  static Stream<LatLng> watchPosition() async* {
    await _ensurePermission();
    await for (final pos in Geolocator.getPositionStream(
      locationSettings: _settings,
    )) {
      yield LatLng(pos.latitude, pos.longitude);
    }
  }

  static Future<void> _ensurePermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      throw Exception('位置情報のアクセスが永続的に拒否されています');
    }
  }
}
