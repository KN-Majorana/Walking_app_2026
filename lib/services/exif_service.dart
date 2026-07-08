import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:exif/exif.dart';
import '../models/location_point.dart';

/// ギャラリー写真のEXIFから位置情報を読み取るサービス
class ExifService {
  ExifService._();

  /// ファイルピッカーで写真を複数選択し、EXIF位置情報を抽出して返す。
  /// 位置情報がない写真はスキップされる。
  static Future<List<LocationPoint>> getLocationsFromGallery() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return [];

    final points = <LocationPoint>[];
    for (final f in result.files) {
      if (f.path == null) continue;
      final file = File(f.path!);
      if (!file.existsSync()) continue;

      try {
        final bytes = await file.readAsBytes();
        final tags = await readExifFromBytes(bytes);
        final loc = _extractLocation(tags);
        if (loc == null) continue;

        // EXIF DateTimeOriginal
        DateTime? ts;
        final dtTag = tags['EXIF DateTimeOriginal'] ??
            tags['Image DateTime'];
        if (dtTag != null) {
          ts = _parseExifDate(dtTag.printable);
        }

        points.add(LocationPoint(
          latitude: loc.$1,
          longitude: loc.$2,
          source: LocationSource.exif,
          timestamp: ts,
          imagePath: f.path,
          label: f.name,
        ));
      } catch (_) {
        // EXIF読み取り失敗はスキップ
      }
    }
    return points;
  }

  // ── 内部ヘルパー ──────────────────────────

  static (double, double)? _extractLocation(Map<String, IfdTag> tags) {
    final latTag  = tags['GPS GPSLatitude'];
    final latRef  = tags['GPS GPSLatitudeRef'];
    final lonTag  = tags['GPS GPSLongitude'];
    final lonRef  = tags['GPS GPSLongitudeRef'];
    if (latTag == null || lonTag == null) return null;

    final lat = _dmsToDecimal(latTag.printable,
        ref: latRef?.printable ?? 'N');
    final lon = _dmsToDecimal(lonTag.printable,
        ref: lonRef?.printable ?? 'E');
    if (lat == null || lon == null) return null;
    return (lat, lon);
  }

  /// "D, M, S" → 十進数度
  static double? _dmsToDecimal(String dms, {required String ref}) {
    try {
      // EXIF format: "[D, M, S]" or "D/1, M/1, S/100" etc.
      final cleaned = dms
          .replaceAll('[', '')
          .replaceAll(']', '')
          .trim();
      final parts = cleaned.split(',').map((s) => s.trim()).toList();
      if (parts.length != 3) return null;

      double parseRational(String s) {
        final slash = s.indexOf('/');
        if (slash < 0) return double.parse(s);
        final num = double.parse(s.substring(0, slash));
        final den = double.parse(s.substring(slash + 1));
        return den == 0 ? 0 : num / den;
      }

      final d = parseRational(parts[0]);
      final m = parseRational(parts[1]);
      final s = parseRational(parts[2]);
      var decimal = d + m / 60 + s / 3600;
      if (ref == 'S' || ref == 'W') decimal = -decimal;
      return decimal;
    } catch (_) {
      return null;
    }
  }

  /// "2024:06:01 12:34:56" → DateTime
  static DateTime? _parseExifDate(String s) {
    try {
      final normalized = s.replaceFirst(':', '-').replaceFirst(':', '-');
      return DateTime.parse(normalized);
    } catch (_) {
      return null;
    }
  }
}
