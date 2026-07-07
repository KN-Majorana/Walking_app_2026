/// 位置情報の取得元
enum LocationSource {
  camera,
  gps,
  exif,
}

/// 緯度・経度＋メタ情報を持つ汎用ポイントモデル
class LocationPoint {
  final double latitude;
  final double longitude;
  final LocationSource source;
  final DateTime? timestamp;
  final String? imagePath;
  final String? label;

  const LocationPoint({
    required this.latitude,
    required this.longitude,
    required this.source,
    this.timestamp,
    this.imagePath,
    this.label,
  });
}
