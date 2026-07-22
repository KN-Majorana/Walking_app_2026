import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../models/location_point.dart';

/// 位置情報ポイントをCSVとしてエクスポートするサービス
class ExportService {
  ExportService._();

  static final _dtFmt = DateFormat('yyyy-MM-dd HH:mm:ss');

  /// [points] をCSVに変換してシェアシートで共有する
  static Future<void> exportToCsv(List<LocationPoint> points) async {
    final buf = StringBuffer();
    buf.writeln('latitude,longitude,source,timestamp,imagePath,label');
    for (final pt in points) {
      final ts = pt.timestamp != null ? _dtFmt.format(pt.timestamp!) : '';
      final src = pt.source.name;
      final img = (pt.imagePath ?? '').replaceAll(',', ' ');
      final lbl = (pt.label ?? '').replaceAll(',', ' ');
      buf.writeln('${pt.latitude},${pt.longitude},$src,$ts,$img,$lbl');
    }

    final dir = await getTemporaryDirectory();
    final file = File(p.join(
      dir.path,
      'export_${DateTime.now().millisecondsSinceEpoch}.csv',
    ));
    await file.writeAsString(buf.toString());

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Map Export',
    );
  }
}
