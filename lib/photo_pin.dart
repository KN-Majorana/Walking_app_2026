import 'package:latlong2/latlong.dart';

/// 撮影した写真とその位置情報、代表色を保持するモデル
class PhotoPin {
  final String id;
  final String imagePath;
  final LatLng position;
  final DateTime takenAt;
  final List<int> colorIds;

  const PhotoPin({
    required this.id,
    required this.imagePath,
    required this.position,
    required this.takenAt,
    this.colorIds = const [],
  });
}
