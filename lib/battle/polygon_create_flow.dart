import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'color_extraction.dart';
import 'location_service.dart';
import 'models/polygon.dart';
import 'photo_service.dart';
import 'services/exif_service.dart';
import 'widgets/create_method_sheet.dart';
import 'widgets/photo_source_sheet.dart';

enum PolygonCreateKind { createNew, addExisting }

/// 多角形作成フローの結果。
///
/// 対戦モード（v6-9）では **色選択ステップを完全にスキップ** するため、
/// 呼び出し側から assignedColorId を渡す。色一致判定は呼び出し側で行う。
class PolygonCreateResult {
  final PolygonCreateKind kind;

  /// 割り当てられた色（colorPalette24 のインデックス）
  final int colorId;

  final String photoPath;

  /// 写真から抽出した主要色（colorPalette24 のインデックス群）
  final List<int> colorIds;

  final LatLng position;
  final DateTime takenAt;

  /// ライブラリ選択時に EXIF が無く現在地/現在時刻へフォールバックしたか
  final bool usedLocationFallback;

  const PolygonCreateResult({
    required this.kind,
    required this.colorId,
    required this.photoPath,
    required this.colorIds,
    required this.position,
    required this.takenAt,
    required this.usedLocationFallback,
  });
}

/// 撮影フロー状態機械。
///
/// 対戦モード（active）中は色選択ステップを飛ばし、割当色に自動固定する。
class PolygonCreateFlow {
  PolygonCreateFlow._();

  /// 対戦モード用エントリ。色はスキップ、[assignedColorId] に固定される。
  ///
  /// ── detached ピン除外フィルタの位置 ─────────────────────
  ///   このフロー内では、pending / attached / detached の判別は行わない
  ///   （純粋に「写真を取ってくる → 位置と色を用意する」責務のみ）。
  ///   detached ピンを候補集合から除外する処理は versus_battle_screen 側
  ///   `_createNewFlow` / `_addExistingFlow` で行っている（そこにも
  ///   コメント付きで実装が明示されている）。
  /// ─────────────────────────────────────────────────────
  static Future<PolygonCreateResult?> runForVersus(
    BuildContext context, {
    required List<WalkPolygon> myConfirmedPolygons,
    required LatLng currentPosition,
    required String battleId,
    required int assignedColorId,
  }) async {
    // ── ステップ A：作成方法 ──
    final hasExisting = myConfirmedPolygons.any((p) =>
        p.colorId == assignedColorId && p.confirmed && p.isActive);
    final method =
        await CreateMethodSheet.show(context, hasExisting: hasExisting);
    if (method == null || !context.mounted) return null;

    // ── ステップ B：写真取得元 ── (色選択はスキップ)
    final source = await PhotoSourceSheet.show(context);
    if (source == null) return null;

    String? path;
    LatLng position = currentPosition;
    DateTime takenAt = DateTime.now();
    bool usedFallback = false;

    if (source == PhotoSource.camera) {
      try {
        position = await LocationService.getCurrentPosition();
      } catch (_) {}
      path = await PhotoService.takeAndSavePhotoForBattle(battleId);
      if (path == null) return null;
    } else {
      path = await PhotoService.pickFromGalleryAndSaveForBattle(battleId);
      if (path == null) return null;

      final exif = await ExifService.readExifForFile(path);
      if (exif.lat != null && exif.lng != null) {
        position = LatLng(exif.lat!, exif.lng!);
      } else {
        usedFallback = true;
      }
      if (exif.timestamp != null) {
        takenAt = exif.timestamp!;
      } else {
        usedFallback = true;
      }
    }

    // ── ステップ D（内部処理）：色判定 ──
    final colorIds = await extractColorIdsFromPath(path);

    return PolygonCreateResult(
      kind: method == PolygonCreateMethod.createNew
          ? PolygonCreateKind.createNew
          : PolygonCreateKind.addExisting,
      colorId: assignedColorId,
      photoPath: path,
      colorIds: colorIds,
      position: position,
      takenAt: takenAt,
      usedLocationFallback: usedFallback,
    );
  }
}
