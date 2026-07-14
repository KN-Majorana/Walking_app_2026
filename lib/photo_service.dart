import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import 'color_module.dart';
import 'photo_pin.dart';

/// 写真撮影と永続化を担うサービス。
class PhotoService {
  static final ImagePicker _picker = ImagePicker();

  /// カメラを起動して写真を撮影し、Use Photo後に画像バイト列だけ返す。
  /// キャンセル時は null を返す。
  static Future<Uint8List?> takePhotoBytes() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );

    if (photo == null) return null;

    return await File(photo.path).readAsBytes();
  }

  static Future<void> deletePhotos(List<PhotoPin> pins) async {
  for (final pin in pins) {
    await deleteSavedImageByIdSql(pin.id);

    final provider = FileImage(File(pin.imagePath));
    await provider.evict();
  }

  imageCache.clear();
  imageCache.clearLiveImages();
}

  /// ユーザーが選択した色IDで写真をDBに保存し、PhotoPinを返す。
  static Future<PhotoPin> savePhotoWithColorIds({
    required Uint8List imageBytes,
    required List<int> colorIds,
    required LatLng position,
  }) async {
    final info = await saveImageInfoByColorIdsSql(
      imageBytes: imageBytes,
      colorIds: colorIds,
      latitude: position.latitude,
      longitude: position.longitude,
    );

    return PhotoPin(
      id: info.id,
      imagePath: info.imagePath,
      position: LatLng(info.latitude, info.longitude),
      takenAt: DateTime.parse(info.timestamp),
      colorIds: info.colorIds,
    );
  }

  /// 互換用：今まで通り「撮影→自動抽出→保存」したい場合に使う。
  /// 今回の色選択フローでは基本使わない。
  static Future<PhotoPin?> takeAndSavePhoto({
    required LatLng position,
  }) async {
    final imageBytes = await takePhotoBytes();
    if (imageBytes == null) return null;

    final colorIds = extractColorIdsFromImageBytes(imageBytes);

    return savePhotoWithColorIds(
      imageBytes: imageBytes,
      colorIds: colorIds,
      position: position,
    );
  }

  /// 起動時などに、保存済みの全写真を PhotoPin の形で取得する。
  static Future<List<PhotoPin>> loadAllPhotoPins() async {
    final infos = await loadAllSavedImagesSql();

    return infos
        .map(
          (info) => PhotoPin(
            id: info.id,
            imagePath: info.imagePath,
            position: LatLng(info.latitude, info.longitude),
            takenAt: DateTime.parse(info.timestamp),
            colorIds: info.colorIds,
          ),
        )
        .toList();
  }
}