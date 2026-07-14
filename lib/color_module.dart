import 'dart:math';
import 'dart:io';
import 'dart:typed_data';

import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class ColorRGB {
  final int r;
  final int g;
  final int b;

  const ColorRGB(this.r, this.g, this.b);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorRGB &&
          r == other.r &&
          g == other.g &&
          b == other.b;

  @override
  int get hashCode => Object.hash(r, g, b);
}

class ObjectResult {
  final List<ColorRGB> colors;

  const ObjectResult({
    required this.colors,
  });
}

// 最重要：代表色を抽出するための関数
ObjectResult extractMainColors(cv.Mat src) {
  final colorSrc = resizeShortSide(src, 128);

  final paletteColors = computePaletteColorsByPixelVoting(
    colorSrc,
    minRatio: 0.10,
    topK: 3,
  );

  colorSrc.dispose();

  return ObjectResult(colors: paletteColors);
  // final colorSrc = resizeShortSide(src, 128);
  // final blurredForColor = cv.blur(colorSrc, (7, 7));

  // final dominantColors = computeDominantColors(
  //   blurredForColor,
  //   binSize: 16,
  //   topK: 3,
  // );

  // // final dominantColors = computeDominantColors(
  // //   colorSrc,
  // //   binSize: 16,
  // //   topK: 3,
  // // );

  // final correctedColors = dominantColors
  //     .map((c) => correctColorSaturation(c, colorSrc, 16))
  //     .toList();

  // final paletteColors = correctedColors
  //     .map((c) => findNearestPaletteColorLab(c))
  //     .toList();

  // final uniquePaletteColors = paletteColors.toSet().toList();

  // colorSrc.dispose();
  // blurredForColor.dispose();

  // return ObjectResult(colors: uniquePaletteColors);
}

List<ColorRGB> computePaletteColorsByPixelVoting(
  cv.Mat image, {
  double minRatio = 0.20,
  int topK = 3,
}) {
  final Map<ColorRGB, double> scores = {};

  final width = image.cols;
  final height = image.rows;

  final cx = (width - 1) / 2.0;
  final cy = (height - 1) / 2.0;

  // 中心重みの強さ
  // 小さいほど中心重視、大きいほど全体を均等に見る
  const sigma = 0.45;
  const invSigma2x2 = 1.0 / (2.0 * sigma * sigma);

  double totalScore = 0.0;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final p = image.at<cv.Vec3b>(y, x);

      final b = p.val1.toInt();
      final g = p.val2.toInt();
      final r = p.val3.toInt();

      // 中心ほどスコアを高くするガウス重み
      final dx = cx == 0 ? 0.0 : (x - cx) / cx;
      final dy = cy == 0 ? 0.0 : (y - cy) / cy;
      final centerWeight = exp(
        -(dx * dx + dy * dy) * invSigma2x2,
      );

      final color = ColorRGB(r, g, b);
      final paletteColor = findNearestPaletteColorLab(color);

      scores[paletteColor] = (scores[paletteColor] ?? 0.0) + centerWeight;
      totalScore += centerWeight;
    }
  }

  if (totalScore == 0.0 || scores.isEmpty) {
    return [];
  }

  final sorted = scores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final result = <ColorRGB>[];

  for (final e in sorted) {
    if (result.length >= topK) break;

    final ratio = e.value / totalScore;

    if (ratio >= minRatio) {
      result.add(e.key);
    }
  }

  // 20%以上がない場合でも、最低1色は返す
  if (result.isEmpty) {
    result.add(sorted.first.key);
  }

  return result;
}

cv.Mat resizeShortSide(cv.Mat src, int targetShortSide) {
  final w = src.cols;
  final h = src.rows;

  late int newW;
  late int newH;

  if (w <= h) {
    newW = targetShortSide;
    newH = (h * targetShortSide / w).round();
  } else {
    newH = targetShortSide;
    newW = (w * targetShortSide / h).round();
  }

  return cv.resize(src, (newW, newH), interpolation: cv.INTER_LINEAR);
}

List<ColorRGB> computeDominantColors(
  cv.Mat image, {
  int binSize = 16,
  double sigma = 0.15,
  int topK = 3,
}) {
  final Map<int, double> binScore = {};

  final width = image.cols;
  final height = image.rows;

  final cx = (width - 1) / 2.0;
  final cy = (height - 1) / 2.0;
  final sx = cx * sigma * 2;
  final sy = cy * sigma * 2;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final p = image.at<cv.Vec3b>(y, x);

      final b = p.val1.toInt();
      final g = p.val2.toInt();
      final r = p.val3.toInt();

      final dx = (x - cx) / sx;
      final dy = (y - cy) / sy;
      final weight = exp(-(dx * dx + dy * dy) / 2.0);

      final key =
          (r ~/ binSize) * 65536 +
          (g ~/ binSize) * 256 +
          (b ~/ binSize);

      binScore[key] = (binScore[key] ?? 0.0) + weight;
    }
  }

  if (binScore.isEmpty) {
    return [const ColorRGB(0, 0, 0)];
  }

  final sortedBins = binScore.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final result = <ColorRGB>[];

  for (int k = 0; k < min(topK, sortedBins.length); k++) {
    final topKey = sortedBins[k].key;

    final rBin = topKey ~/ 65536;
    final gBin = (topKey % 65536) ~/ 256;
    final bBin = topKey % 256;

    int sumR = 0;
    int sumG = 0;
    int sumB = 0;
    int count = 0;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final p = image.at<cv.Vec3b>(y, x);

        final b = p.val1.toInt();
        final g = p.val2.toInt();
        final r = p.val3.toInt();

        if (r ~/ binSize == rBin &&
            g ~/ binSize == gBin &&
            b ~/ binSize == bBin) {
          sumR += r;
          sumG += g;
          sumB += b;
          count++;
        }
      }
    }

    if (count > 0) {
      result.add(ColorRGB(sumR ~/ count, sumG ~/ count, sumB ~/ count));
    }
  }

  return result;
}

ColorRGB correctColorSaturation(
  ColorRGB blurredColor,
  cv.Mat original,
  int binSize,
) {
  final br = blurredColor.r;
  final bg = blurredColor.g;
  final bb = blurredColor.b;

  final blurredHsv = rgbToHsv(br, bg, bb);
  final hue = blurredHsv[0];

  double sumS = 0;
  double sumV = 0;
  int count = 0;

  final rBin = br ~/ binSize;
  final gBin = bg ~/ binSize;
  final bBin = bb ~/ binSize;

  for (int y = 0; y < original.rows; y++) {
    for (int x = 0; x < original.cols; x++) {
      final p = original.at<cv.Vec3b>(y, x);

      final b = p.val1.toInt();
      final g = p.val2.toInt();
      final r = p.val3.toInt();

      if (r ~/ binSize == rBin &&
          g ~/ binSize == gBin &&
          b ~/ binSize == bBin) {
        final hsv = rgbToHsv(r, g, b);
        sumS += hsv[1];
        sumV += hsv[2];
        count++;
      }
    }
  }

  if (count == 0) return blurredColor;

  final corrected = hsvToRgb(hue, sumS / count, sumV / count);
  return ColorRGB(corrected[0], corrected[1], corrected[2]);
}

List<double> rgbToHsv(int r, int g, int b) {
  final rf = r / 255.0;
  final gf = g / 255.0;
  final bf = b / 255.0;
  final maxC = [rf, gf, bf].reduce(max);
  final minC = [rf, gf, bf].reduce(min);
  final delta = maxC - minC;

  double h = 0;
  if (delta != 0) {
    if (maxC == rf) {
      h = 60 * (((gf - bf) / delta) % 6);
    } else if (maxC == gf) {
      h = 60 * (((bf - rf) / delta) + 2);
    } else {
      h = 60 * (((rf - gf) / delta) + 4);
    }
  }
  if (h < 0) h += 360;

  final s = maxC == 0 ? 0.0 : delta / maxC;
  return [h, s, maxC];
}

List<int> hsvToRgb(double h, double s, double v) {
  final c = v * s;
  final x = c * (1 - ((h / 60) % 2 - 1).abs());
  final m = v - c;

  double rf, gf, bf;
  if (h < 60) {
    rf = c;
    gf = x;
    bf = 0;
  } else if (h < 120) {
    rf = x;
    gf = c;
    bf = 0;
  } else if (h < 180) {
    rf = 0;
    gf = c;
    bf = x;
  } else if (h < 240) {
    rf = 0;
    gf = x;
    bf = c;
  } else if (h < 300) {
    rf = x;
    gf = 0;
    bf = c;
  } else {
    rf = c;
    gf = 0;
    bf = x;
  }

  return [
    ((rf + m) * 255).round().clamp(0, 255),
    ((gf + m) * 255).round().clamp(0, 255),
    ((bf + m) * 255).round().clamp(0, 255),
  ];
}

// final List<ColorRGB> colorPalette24 = [
//   const ColorRGB(0, 0, 0),
//   const ColorRGB(85, 85, 85),
//   const ColorRGB(170, 170, 170),
//   const ColorRGB(255, 255, 255),
//   const ColorRGB(255, 0, 0),
//   const ColorRGB(192, 0, 0),
//   const ColorRGB(255, 192, 203),
//   const ColorRGB(255, 128, 0),
//   const ColorRGB(255, 192, 0),
//   const ColorRGB(255, 255, 0),
//   const ColorRGB(192, 255, 0),
//   const ColorRGB(128, 255, 0),
//   const ColorRGB(0, 200, 0),
//   const ColorRGB(0, 100, 0),
//   const ColorRGB(0, 255, 255),
//   const ColorRGB(0, 192, 255),
//   const ColorRGB(0, 0, 255),
//   const ColorRGB(0, 0, 128),
//   const ColorRGB(128, 0, 255),
//   const ColorRGB(255, 0, 255),
//   const ColorRGB(139, 69, 19),
//   const ColorRGB(101, 67, 33),
//   const ColorRGB(210, 180, 140),
//   const ColorRGB(255, 220, 177),
// ];

// final List<String> colorNames24 = [
//   'Black',
//   'DarkGray',
//   'LightGray',
//   'White',
//   'Red',
//   'DarkRed',
//   'Pink',
//   'Orange',
//   'Amber',
//   'Yellow',
//   'YellowGreen',
//   'Lime',
//   'Green',
//   'DarkGreen',
//   'Cyan',
//   'SkyBlue',
//   'Blue',
//   'Navy',
//   'Purple',
//   'Magenta',
//   'Brown',
//   'DarkBrown',
//   'Tan',
//   'LightOrange',
// ];

// final List<ColorRGB> colorPalette24 = [
//   const ColorRGB(0, 0, 0),        // Black
//   const ColorRGB(255, 255, 255),  // White
//   const ColorRGB(255, 0, 0),      // Red
//   const ColorRGB(255, 192, 203),  // Pink
//   const ColorRGB(255, 128, 0),    // Orange
//   const ColorRGB(255, 255, 0),    // Yellow
//   const ColorRGB(0, 200, 0),      // Green
//   const ColorRGB(0, 255, 255),    // Cyan
//   const ColorRGB(0, 192, 255),    // SkyBlue
//   const ColorRGB(0, 0, 255),      // Blue
//   const ColorRGB(128, 0, 255),    // Purple
//   const ColorRGB(139, 69, 19),    // Brown
// ];

final List<ColorRGB> colorPalette24 = [
  const ColorRGB(0, 0, 0),        // Black
  const ColorRGB(255, 255, 255),  // White
  const ColorRGB(255, 0, 0),      // Red
  const ColorRGB(255, 192, 203),  // Pink
  const ColorRGB(255, 128, 0),    // Orange
  const ColorRGB(255, 255, 0),    // Yellow
  const ColorRGB(0, 200, 0),      // Green
  const ColorRGB(0, 255, 255),    // Cyan
  const ColorRGB(0, 192, 255),    // SkyBlue
  const ColorRGB(0, 0, 255),      // Blue
  const ColorRGB(255, 0, 255),    // Purple
  const ColorRGB(139, 69, 19),    // Brown
];

final List<String> colorNames24 = [
  'Black',
  'White',
  'Red',
  'Pink',
  'Orange',
  'Yellow',
  'Green',
  'Cyan',
  'SkyBlue',
  'Blue',
  'Purple',
  'Brown',
];

List<String> getColorNamesFromIds(List<int> colorIds) {
  return colorIds
      .where((id) => id >= 0 && id < colorNames24.length)
      .map((id) => colorNames24[id])
      .toList();
}

ColorRGB? getColorFromId(int colorId) {
  if (colorId < 0 || colorId >= colorPalette24.length) return null;
  return colorPalette24[colorId];
}

List<int> extractColorIdsFromImageBytes(Uint8List imageBytes) {
  final src = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
  final result = extractMainColors(src);
  src.dispose();

  final colorIds = result.colors
      .map((color) => colorPalette24.indexOf(color))
      .where((idx) => idx >= 0)
      .toList();

  return colorIds;
}

class _PaletteCandidate {
  final ColorRGB color;
  final double hueDiff;
  final double chromaDiff;
  final double paletteChroma;

  const _PaletteCandidate({
    required this.color,
    required this.hueDiff,
    required this.chromaDiff,
    required this.paletteChroma,
  });
}

double _angleDiff(double x, double y) {
  final diff = (x - y).abs();
  return diff > pi ? 2 * pi - diff : diff;
}

// ColorRGB findNearestPaletteColorLab(ColorRGB color) {
//   final inputLab = rgbToLabColor(color);

//   ColorRGB nearest = colorPalette24.first;
//   double minDist = double.infinity;

//   for (final p in colorPalette24) {
//     final paletteLab = rgbToLabColor(p);

//     final dL = inputLab[0] - paletteLab[0];
//     final da = inputLab[1] - paletteLab[1];
//     final db = inputLab[2] - paletteLab[2];

//     final dist = dL * dL + da * da + db * db;

//     if (dist < minDist) {
//       minDist = dist;
//       nearest = p;
//     }
//   }

//   return nearest;
// }

ColorRGB findNearestPaletteColorLab(ColorRGB color) {
  final inputLab = rgbToLabColor(color);

  final inputL = inputLab[0];

  // OpenCV Lab は a,b が 128 中心なので、0中心に直す
  final inputA = inputLab[1] - 128.0;
  final inputB = inputLab[2] - 128.0;

  // ab平面上で中心からの距離
  final inputChroma = sqrt(inputA * inputA + inputB * inputB);

  // 中心にかなり近い色は、色相角が不安定なので L 方向だけで Black / White 判定
  //
  // OpenCV Lab の a,b だと、完全な白黒は中心付近になります。
  // しきい値はまず 10〜15 くらいがおすすめです。
  const neutralChromaThreshold = 10.0;

  if (inputChroma < neutralChromaThreshold) {
    return _nearestPaletteColorByLightnessOnly(inputL);
  }

  final inputHue = atan2(inputB, inputA);

  final candidates = <_PaletteCandidate>[];

  for (final p in colorPalette24) {
    final paletteLab = rgbToLabColor(p);

    final paletteA = paletteLab[1] - 128.0;
    final paletteB = paletteLab[2] - 128.0;

    final paletteChroma = sqrt(
      paletteA * paletteA + paletteB * paletteB,
    );

    // Black / White などの無彩色は、有彩色の候補から外す
    if (paletteChroma < neutralChromaThreshold) {
      continue;
    }

    final paletteHue = atan2(paletteB, paletteA);

    // まず角度差で大まかに分類する
    final hueDiff = _angleDiff(inputHue, paletteHue);

    // その後、中心からの距離の近さで分類する
    final chromaDiff = (inputChroma - paletteChroma).abs();

    candidates.add(
      _PaletteCandidate(
        color: p,
        hueDiff: hueDiff,
        chromaDiff: chromaDiff,
        paletteChroma: paletteChroma,
      ),
    );
  }

  if (candidates.isEmpty) {
    return _nearestPaletteColorByLightnessOnly(inputL);
  }

  // まず ab 平面の角度が近い順に並べる
  candidates.sort((a, b) => a.hueDiff.compareTo(b.hueDiff));

  final bestHueDiff = candidates.first.hueDiff;

  // 一番近い角度から、どこまでを「同じ方向の色」とみなすか
  //
  // 0.45 rad ≒ 25.8度
  // Pink と Red を同じ赤系候補に入れたいなら、0.45くらいが扱いやすいです。
  const hueMargin = 0.25;

  final hueCandidates = candidates
      .where((c) => c.hueDiff <= bestHueDiff + hueMargin)
      .toList();

  // 角度が近い候補の中で、中心からの距離が近い色を選ぶ
  hueCandidates.sort((a, b) {
    final cmpChroma = a.chromaDiff.compareTo(b.chromaDiff);
    if (cmpChroma != 0) return cmpChroma;

    // chroma差が同じくらいなら、角度が近い方を優先
    return a.hueDiff.compareTo(b.hueDiff);
  });

  return hueCandidates.first.color;
}

ColorRGB _nearestPaletteColorByLightnessOnly(double inputL) {
  ColorRGB nearest = colorPalette24.first;
  double minDiff = double.infinity;

  for (final p in colorPalette24) {
    final idx = colorPalette24.indexOf(p);
    final name = colorNames24[idx];

    if (name != 'Black' && name != 'White') {
      continue;
    }

    final lab = rgbToLabColor(p);
    final diff = (inputL - lab[0]).abs();

    if (diff < minDiff) {
      minDiff = diff;
      nearest = p;
    }
  }

  return nearest;
}

ColorRGB _nearestPaletteColorByLabDistance(ColorRGB color) {
  final inputLab = rgbToLabColor(color);

  ColorRGB nearest = colorPalette24.first;
  double minDist = double.infinity;

  for (final p in colorPalette24) {
    final paletteLab = rgbToLabColor(p);

    final dL = inputLab[0] - paletteLab[0];
    final da = inputLab[1] - paletteLab[1];
    final db = inputLab[2] - paletteLab[2];

    final dist = dL * dL + da * da + db * db;

    if (dist < minDist) {
      minDist = dist;
      nearest = p;
    }
  }

  return nearest;
}

List<double> rgbToLabColor(ColorRGB color) {
  final mat = cv.Mat.fromList(
    1,
    1,
    cv.MatType.CV_8UC3,
    [color.b, color.g, color.r],
  );

  final lab = cv.cvtColor(mat, cv.COLOR_BGR2Lab);
  final p = lab.at<cv.Vec3b>(0, 0);

  final l = p.val1.toDouble();
  final a = p.val2.toDouble();
  final b = p.val3.toDouble();

  mat.dispose();
  lab.dispose();

  return [l, a, b];
}

// ====================================================
// 永続化 (sqflite)
// ====================================================

class SavedImageInfo {
  final String id;
  final String imagePath;
  final List<int> colorIds;
  final double latitude;
  final double longitude;
  final String timestamp;

  const SavedImageInfo({
    required this.id,
    required this.imagePath,
    required this.colorIds,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imagePath': imagePath,
      'colorIds': colorIds,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp,
    };
  }
}

Database? _db;

Future<Directory> getSavedImagesDirectory() async {
  final dir = await getApplicationDocumentsDirectory();
  final imagesDir = Directory(p.join(dir.path, 'images'));

  if (!await imagesDir.exists()) {
    await imagesDir.create(recursive: true);
  }

  return imagesDir;
}

Future<String> resolveSavedImagePath(String storedPath) async {
  // すでに絶対パスで、実ファイルが存在する場合はそのまま使う
  final directFile = File(storedPath);
  if (storedPath.startsWith('/') && await directFile.exists()) {
    return storedPath;
  }

  final dir = await getApplicationDocumentsDirectory();

  // DBに images/xxx.jpg のような相対パスが入っている場合
  final relativeFile = File(p.join(dir.path, storedPath));
  if (await relativeFile.exists()) {
    return relativeFile.path;
  }

  // 古いDBに絶対パスが残っている場合の救済
  // basenameだけ取り出して、現在の Documents/images/ にあるか探す
  final fallbackFile = File(
    p.join(dir.path, 'images', p.basename(storedPath)),
  );

  if (await fallbackFile.exists()) {
    return fallbackFile.path;
  }

  // 見つからなければ最後に相対解決したパスを返す
  // 呼び出し側で exists チェックする
  return relativeFile.path;
}

Future<Database> getAppDatabase() async {
  if (_db != null) return _db!;

  final dir = await getApplicationDocumentsDirectory();
  final dbPath = p.join(dir.path, 'color_app.db');

  _db = await openDatabase(
    dbPath,
    version: 1,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE images (
          id TEXT PRIMARY KEY,
          imagePath TEXT NOT NULL,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          timestamp TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE image_colors (
          imageId TEXT NOT NULL,
          colorId INTEGER NOT NULL,
          PRIMARY KEY (imageId, colorId),
          FOREIGN KEY (imageId) REFERENCES images(id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        CREATE INDEX idx_image_colors_colorId
        ON image_colors(colorId)
      ''');
    },
  );

  return _db!;
}

/// 写真バイト列を /images/{id}.jpg に保存し、代表色とともに DB に登録する。
Future<SavedImageInfo> saveImageInfoByColorIdsSql({
  required Uint8List imageBytes,
  required List<int> colorIds,
  required double latitude,
  required double longitude,
}) async {
  final imagesDir = await getSavedImagesDirectory();

  final now = DateTime.now();
  final id = '${now.microsecondsSinceEpoch}_${Random().nextInt(999999)}';
  final timestamp = now.toIso8601String();

  final fileName = '$id.jpg';
  final relativeImagePath = p.join('images', fileName);
  final imageFile = File(p.join(imagesDir.path, fileName));

  await imageFile.writeAsBytes(imageBytes, flush: true);

  if (!await imageFile.exists()) {
    throw Exception('画像ファイルの保存に失敗しました');
  }

  final info = SavedImageInfo(
    id: id,
    imagePath: imageFile.path,
    colorIds: colorIds,
    latitude: latitude,
    longitude: longitude,
    timestamp: timestamp,
  );

  final db = await getAppDatabase();

  await db.transaction((txn) async {
    await txn.insert(
      'images',
      {
        'id': info.id,
        // 'imagePath': info.imagePath,
        'imagePath': relativeImagePath,
        'latitude': info.latitude,
        'longitude': info.longitude,
        'timestamp': info.timestamp,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    for (final colorId in colorIds) {
      await txn.insert(
        'image_colors',
        {
          'imageId': info.id,
          'colorId': colorId,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  });

  return info;
}

/// 撮影バイト列から代表色抽出 → DB保存までを一気に行うヘルパー。
/// PhotoService から呼ばれる想定。
Future<SavedImageInfo> extractAndSavePhoto({
  required Uint8List imageBytes,
  required double latitude,
  required double longitude,
}) async {
  final src = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
  final result = extractMainColors(src);
  src.dispose();

  final colorIds = result.colors
      .map((c) => colorPalette24.indexOf(c))
      .where((idx) => idx >= 0)
      .toList();

  return await saveImageInfoByColorIdsSql(
    imageBytes: imageBytes,
    colorIds: colorIds,
    latitude: latitude,
    longitude: longitude,
  );
}

/// 保存済みの全画像を新しい順で取得する。
Future<List<SavedImageInfo>> loadAllSavedImagesSql() async {
  final db = await getAppDatabase();

  final rows = await db.query('images', orderBy: 'timestamp DESC');

  final results = <SavedImageInfo>[];

  for (final row in rows) {
    final imageId = row['id'] as String;
    final storedPath = row['imagePath'] as String;

    final resolvedPath = await resolveSavedImagePath(storedPath);

    // 画像ファイルが存在しない場合はDBからも削除
    if (!await File(resolvedPath).exists()) {
      await db.delete(
        'image_colors',
        where: 'imageId = ?',
        whereArgs: [imageId],
      );

      await db.delete(
        'images',
        where: 'id = ?',
        whereArgs: [imageId],
      );

      continue;
    }

    final colorRows = await db.query(
      'image_colors',
      where: 'imageId = ?',
      whereArgs: [imageId],
    );

    final ids = colorRows.map((r) => r['colorId'] as int).toList();

    results.add(
      SavedImageInfo(
        id: imageId,
        imagePath: resolvedPath, // UIには現在有効な絶対パスを渡す
        colorIds: ids,
        latitude: row['latitude'] as double,
        longitude: row['longitude'] as double,
        timestamp: row['timestamp'] as String,
      ),
    );
  }

  return results;
}

Future<List<SavedImageInfo>> getImagesByColorIdSql(int colorId) async {
  final db = await getAppDatabase();

  final rows = await db.rawQuery(
    '''
    SELECT images.*
    FROM images
    JOIN image_colors
      ON images.id = image_colors.imageId
    WHERE image_colors.colorId = ?
    ORDER BY images.timestamp DESC
    ''',
    [colorId],
  );

  final results = <SavedImageInfo>[];

  for (final row in rows) {
    final imageId = row['id'] as String;
    final storedPath = row['imagePath'] as String;

    final resolvedPath = await resolveSavedImagePath(storedPath);

    if (!await File(resolvedPath).exists()) {
      await db.delete(
        'image_colors',
        where: 'imageId = ?',
        whereArgs: [imageId],
      );

      await db.delete(
        'images',
        where: 'id = ?',
        whereArgs: [imageId],
      );

      continue;
    }

    final colorRows = await db.query(
      'image_colors',
      where: 'imageId = ?',
      whereArgs: [imageId],
    );

    final ids = colorRows.map((r) => r['colorId'] as int).toList();

    results.add(
      SavedImageInfo(
        id: imageId,
        imagePath: resolvedPath,
        colorIds: ids,
        latitude: row['latitude'] as double,
        longitude: row['longitude'] as double,
        timestamp: row['timestamp'] as String,
      ),
    );
  }

  return results;
}

Future<void> deleteSavedImageByIdSql(String imageId) async {
  final db = await getAppDatabase();

  final rows = await db.query(
    'images',
    where: 'id = ?',
    whereArgs: [imageId],
    limit: 1,
  );

  if (rows.isEmpty) return;

  final storedPath = rows.first['imagePath'] as String;
  final resolvedPath = await resolveSavedImagePath(storedPath);

  final file = File(resolvedPath);
  if (await file.exists()) {
    await file.delete();
  }

  await db.delete(
    'image_colors',
    where: 'imageId = ?',
    whereArgs: [imageId],
  );

  await db.delete(
    'images',
    where: 'id = ?',
    whereArgs: [imageId],
  );
}








// import 'dart:io';
// import 'dart:math';
// import 'dart:typed_data';

// import 'package:opencv_dart/opencv.dart' as cv;
// import 'package:path_provider/path_provider.dart';
// import 'package:sqflite/sqflite.dart';
// import 'package:path/path.dart' as p;

// class ColorRGB {
//   final int r;
//   final int g;
//   final int b;

//   const ColorRGB(this.r, this.g, this.b);

//   @override
//   bool operator ==(Object other) =>
//       identical(this, other) ||
//       other is ColorRGB &&
//           r == other.r &&
//           g == other.g &&
//           b == other.b;

//   @override
//   int get hashCode => Object.hash(r, g, b);
// }

// class ObjectResult {
//   final List<ColorRGB> colors;

//   const ObjectResult({
//     required this.colors,
//   });
// }

// class PaletteColorScore {
//   final ColorRGB color;
//   final double ratio;

//   const PaletteColorScore({
//     required this.color,
//     required this.ratio,
//   });
// }

// // ====================================================
// // 代表色抽出
// // ====================================================

// ObjectResult extractMainColors(cv.Mat src) {
//   final colorSrc = resizeShortSide(src, 128);

//   final colorScores = computePaletteColorRatios(
//     colorSrc,
//     minRatio: 0.08,
//     maxColors: 3,
//   );

//   colorSrc.dispose();

//   if (colorScores.isEmpty) {
//     return const ObjectResult(colors: [ColorRGB(0, 0, 0)]);
//   }

//   return ObjectResult(
//     colors: colorScores.map((score) => score.color).toList(),
//   );
// }

// cv.Mat resizeShortSide(cv.Mat src, int targetShortSide) {
//   final width = src.cols;
//   final height = src.rows;

//   late int newWidth;
//   late int newHeight;

//   if (width <= height) {
//     newWidth = targetShortSide;
//     newHeight = (height * targetShortSide / width).round();
//   } else {
//     newHeight = targetShortSide;
//     newWidth = (width * targetShortSide / height).round();
//   }

//   return cv.resize(
//     src,
//     (newWidth, newHeight),
//     interpolation: cv.INTER_LINEAR,
//   );
// }

// /// 各ピクセルを12色パレットへ分類し、割合が閾値以上の上位色を返す。
// List<PaletteColorScore> computePaletteColorRatios(
//   cv.Mat image, {
//   double minRatio = 0.08,
//   int maxColors = 3,
// }) {
//   final scores = List<double>.filled(colorPalette24.length, 0.0);
//   double totalScore = 0.0;

//   final width = image.cols;
//   final height = image.rows;

//   final cx = (width - 1) / 2.0;
//   final cy = (height - 1) / 2.0;

//   final sx = max(cx * 0.70, 1.0);
//   final sy = max(cy * 0.70, 1.0);

//   for (int y = 0; y < height; y++) {
//     for (int x = 0; x < width; x++) {
//       final pixel = image.at<cv.Vec3b>(y, x);

//       final b = pixel.val1.toInt();
//       final g = pixel.val2.toInt();
//       final r = pixel.val3.toInt();

//       final color = ColorRGB(r, g, b);
//       final paletteColor = classifyPixelToPalette(color);
//       final colorIndex = colorPalette24.indexOf(paletteColor);

//       if (colorIndex < 0) continue;

//       final dx = (x - cx) / sx;
//       final dy = (y - cy) / sy;

//       // 中央を少しだけ重視。
//       // 端の被写体を消しすぎないように、重みは弱め。
//       final centerWeight = 0.80 + 0.20 * exp(-(dx * dx + dy * dy) / 2.0);

//       scores[colorIndex] += centerWeight;
//       totalScore += centerWeight;
//     }
//   }

//   if (totalScore <= 0) {
//     return [];
//   }

//   final results = <PaletteColorScore>[];

//   for (int i = 0; i < scores.length; i++) {
//     final ratio = scores[i] / totalScore;
//     final color = colorPalette24[i];

//     // 白・黒・グレーは背景や影で入りやすいので少し厳しめ。
//     final isMonoColor = i == 0 || i == 1 || i == 2;

//     final threshold = isMonoColor ? max(minRatio, 0.10) : minRatio;

//     if (ratio >= threshold) {
//       results.add(
//         PaletteColorScore(
//           color: color,
//           ratio: ratio,
//         ),
//       );
//     }
//   }

//   results.sort((a, b) => b.ratio.compareTo(a.ratio));

//   if (results.length > maxColors) {
//     return results.sublist(0, maxColors);
//   }

//   return results;
// }

// /// 1ピクセルを12色パレットのどれかへ分類する。
// ColorRGB classifyPixelToPalette(ColorRGB color) {
//   final hsv = rgbToHsv(color.r, color.g, color.b);
//   final saturation = hsv[1];
//   final value = hsv[2];

//   // 低彩度系は先に分類する。
//   // 影がある白もWhiteに残りやすくする。
//   if (saturation < 0.14) {
//     if (value > 0.62) {
//       return const ColorRGB(255, 255, 255); // White
//     }

//     if (value < 0.22) {
//       return const ColorRGB(0, 0, 0); // Black
//     }

//     return const ColorRGB(100, 100, 100); // Gray
//   }

//   // 明るくて彩度が低めならWhite扱い。
//   // 白い壁・白い紙・白い服が薄いピンクや黄色に寄るのを防ぐ。
//   if (value > 0.78 && saturation < 0.22) {
//     return const ColorRGB(255, 255, 255); // White
//   }

//   return findNearestPaletteColorLab(color);
// }

// // ====================================================
// // 色変換
// // ====================================================

// List<double> rgbToHsv(int r, int g, int b) {
//   final rf = r / 255.0;
//   final gf = g / 255.0;
//   final bf = b / 255.0;

//   final maxC = [rf, gf, bf].reduce(max);
//   final minC = [rf, gf, bf].reduce(min);
//   final delta = maxC - minC;

//   double h = 0;

//   if (delta != 0) {
//     if (maxC == rf) {
//       h = 60 * (((gf - bf) / delta) % 6);
//     } else if (maxC == gf) {
//       h = 60 * (((bf - rf) / delta) + 2);
//     } else {
//       h = 60 * (((rf - gf) / delta) + 4);
//     }
//   }

//   if (h < 0) h += 360;

//   final s = maxC == 0 ? 0.0 : delta / maxC;

//   return [h, s, maxC];
// }

// List<int> hsvToRgb(double h, double s, double v) {
//   final c = v * s;
//   final x = c * (1 - ((h / 60) % 2 - 1).abs());
//   final m = v - c;

//   double rf;
//   double gf;
//   double bf;

//   if (h < 60) {
//     rf = c;
//     gf = x;
//     bf = 0;
//   } else if (h < 120) {
//     rf = x;
//     gf = c;
//     bf = 0;
//   } else if (h < 180) {
//     rf = 0;
//     gf = c;
//     bf = x;
//   } else if (h < 240) {
//     rf = 0;
//     gf = x;
//     bf = c;
//   } else if (h < 300) {
//     rf = x;
//     gf = 0;
//     bf = c;
//   } else {
//     rf = c;
//     gf = 0;
//     bf = x;
//   }

//   return [
//     ((rf + m) * 255).round().clamp(0, 255),
//     ((gf + m) * 255).round().clamp(0, 255),
//     ((bf + m) * 255).round().clamp(0, 255),
//   ];
// }

// // ====================================================
// // 12色パレット
// // 変数名は既存コード互換のため colorPalette24 のまま
// // ====================================================

// final List<ColorRGB> colorPalette24 = [
//   const ColorRGB(0, 0, 0),        // Black
//   const ColorRGB(100, 100, 100),  // Gray
//   const ColorRGB(255, 255, 255),  // White
//   const ColorRGB(255, 0, 0),      // Red
//   const ColorRGB(255, 105, 180),  // Pink
//   const ColorRGB(255, 128, 0),    // Orange
//   const ColorRGB(255, 255, 0),    // Yellow
//   const ColorRGB(0, 200, 0),      // Green
//   const ColorRGB(0, 192, 255),    // SkyBlue
//   const ColorRGB(0, 0, 255),      // Blue
//   const ColorRGB(128, 0, 255),    // Purple
//   const ColorRGB(139, 69, 19),    // Brown
// ];

// final List<String> colorNames24 = [
//   'Black',
//   'Gray',
//   'White',
//   'Red',
//   'Pink',
//   'Orange',
//   'Yellow',
//   'Green',
//   'SkyBlue',
//   'Blue',
//   'Purple',
//   'Brown',
// ];

// List<String> getColorNamesFromIds(List<int> colorIds) {
//   return colorIds
//       .where((id) => id >= 0 && id < colorNames24.length)
//       .map((id) => colorNames24[id])
//       .toList();
// }

// ColorRGB findNearestPaletteColorLab(ColorRGB color) {
//   final hsv = rgbToHsv(color.r, color.g, color.b);
//   final saturation = hsv[1];
//   final value = hsv[2];

//   // 影がかかった白をGrayに落としすぎないための補正。
//   if (saturation < 0.16 && value > 0.62) {
//     return const ColorRGB(255, 255, 255);
//   }

//   // かなり暗い低彩度だけBlack扱い。
//   if (saturation < 0.16 && value < 0.22) {
//     return const ColorRGB(0, 0, 0);
//   }

//   // 中間の低彩度はGray。
//   if (saturation < 0.16) {
//     return const ColorRGB(100, 100, 100);
//   }

//   final inputLab = rgbToLabColor(color);

//   ColorRGB nearest = colorPalette24.first;
//   double minDist = double.infinity;

//   for (final paletteColor in colorPalette24) {
//     final paletteLab = rgbToLabColor(paletteColor);

//     final dL = inputLab[0] - paletteLab[0];
//     final da = inputLab[1] - paletteLab[1];
//     final db = inputLab[2] - paletteLab[2];

//     final dist = dL * dL + da * da + db * db;

//     if (dist < minDist) {
//       minDist = dist;
//       nearest = paletteColor;
//     }
//   }

//   return nearest;
// }

// List<double> rgbToLabColor(ColorRGB color) {
//   final mat = cv.Mat.fromList(
//     1,
//     1,
//     cv.MatType.CV_8UC3,
//     [color.b, color.g, color.r],
//   );

//   final lab = cv.cvtColor(mat, cv.COLOR_BGR2Lab);
//   final pixel = lab.at<cv.Vec3b>(0, 0);

//   final l = pixel.val1.toDouble();
//   final a = pixel.val2.toDouble();
//   final b = pixel.val3.toDouble();

//   mat.dispose();
//   lab.dispose();

//   return [l, a, b];
// }

// // ====================================================
// // 永続化 sqflite
// // ====================================================

// class SavedImageInfo {
//   final String id;
//   final String imagePath;
//   final List<int> colorIds;
//   final double latitude;
//   final double longitude;
//   final String timestamp;

//   const SavedImageInfo({
//     required this.id,
//     required this.imagePath,
//     required this.colorIds,
//     required this.latitude,
//     required this.longitude,
//     required this.timestamp,
//   });

//   Map<String, dynamic> toJson() {
//     return {
//       'id': id,
//       'imagePath': imagePath,
//       'colorIds': colorIds,
//       'latitude': latitude,
//       'longitude': longitude,
//       'timestamp': timestamp,
//     };
//   }
// }

// Database? _db;

// Future<Directory> getSavedImagesDirectory() async {
//   final dir = await getApplicationDocumentsDirectory();
//   final imagesDir = Directory(p.join(dir.path, 'images'));

//   if (!await imagesDir.exists()) {
//     await imagesDir.create(recursive: true);
//   }

//   return imagesDir;
// }

// Future<String> resolveSavedImagePath(String storedPath) async {
//   final directFile = File(storedPath);

//   if (storedPath.startsWith('/') && await directFile.exists()) {
//     return storedPath;
//   }

//   final dir = await getApplicationDocumentsDirectory();

//   final relativeFile = File(p.join(dir.path, storedPath));
//   if (await relativeFile.exists()) {
//     return relativeFile.path;
//   }

//   final fallbackFile = File(
//     p.join(dir.path, 'images', p.basename(storedPath)),
//   );

//   if (await fallbackFile.exists()) {
//     return fallbackFile.path;
//   }

//   return relativeFile.path;
// }

// Future<Database> getAppDatabase() async {
//   if (_db != null) return _db!;

//   final dir = await getApplicationDocumentsDirectory();
//   final dbPath = p.join(dir.path, 'color_app.db');

//   _db = await openDatabase(
//     dbPath,
//     version: 1,
//     onCreate: (db, version) async {
//       await db.execute('''
//         CREATE TABLE images (
//           id TEXT PRIMARY KEY,
//           imagePath TEXT NOT NULL,
//           latitude REAL NOT NULL,
//           longitude REAL NOT NULL,
//           timestamp TEXT NOT NULL
//         )
//       ''');

//       await db.execute('''
//         CREATE TABLE image_colors (
//           imageId TEXT NOT NULL,
//           colorId INTEGER NOT NULL,
//           PRIMARY KEY (imageId, colorId),
//           FOREIGN KEY (imageId) REFERENCES images(id) ON DELETE CASCADE
//         )
//       ''');

//       await db.execute('''
//         CREATE INDEX idx_image_colors_colorId
//         ON image_colors(colorId)
//       ''');
//     },
//   );

//   return _db!;
// }

// /// 写真バイト列をアプリDocuments/images内に保存し、代表色とともにDBへ登録する。
// Future<SavedImageInfo> saveImageInfoByColorIdsSql({
//   required Uint8List imageBytes,
//   required List<int> colorIds,
//   required double latitude,
//   required double longitude,
// }) async {
//   final imagesDir = await getSavedImagesDirectory();

//   final now = DateTime.now();
//   final id = '${now.microsecondsSinceEpoch}_${Random().nextInt(999999)}';
//   final timestamp = now.toIso8601String();

//   final fileName = '$id.jpg';
//   final relativeImagePath = p.join('images', fileName);
//   final imageFile = File(p.join(imagesDir.path, fileName));

//   await imageFile.writeAsBytes(imageBytes, flush: true);

//   if (!await imageFile.exists()) {
//     throw Exception('画像ファイルの保存に失敗しました');
//   }

//   final info = SavedImageInfo(
//     id: id,
//     imagePath: imageFile.path,
//     colorIds: colorIds,
//     latitude: latitude,
//     longitude: longitude,
//     timestamp: timestamp,
//   );

//   final db = await getAppDatabase();

//   await db.transaction((txn) async {
//     await txn.insert(
//       'images',
//       {
//         'id': info.id,
//         'imagePath': relativeImagePath,
//         'latitude': info.latitude,
//         'longitude': info.longitude,
//         'timestamp': info.timestamp,
//       },
//       conflictAlgorithm: ConflictAlgorithm.replace,
//     );

//     for (final colorId in colorIds) {
//       await txn.insert(
//         'image_colors',
//         {
//           'imageId': info.id,
//           'colorId': colorId,
//         },
//         conflictAlgorithm: ConflictAlgorithm.ignore,
//       );
//     }
//   });

//   return info;
// }

// /// 撮影バイト列から代表色抽出 → DB保存までを一括実行する。
// Future<SavedImageInfo> extractAndSavePhoto({
//   required Uint8List imageBytes,
//   required double latitude,
//   required double longitude,
// }) async {
//   final src = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
//   final result = extractMainColors(src);
//   src.dispose();

//   final colorIds = result.colors
//       .map((color) => colorPalette24.indexOf(color))
//       .where((idx) => idx >= 0)
//       .toList();

//   return await saveImageInfoByColorIdsSql(
//     imageBytes: imageBytes,
//     colorIds: colorIds,
//     latitude: latitude,
//     longitude: longitude,
//   );
// }

// /// 保存済みの全画像を新しい順で取得する。
// Future<List<SavedImageInfo>> loadAllSavedImagesSql() async {
//   final db = await getAppDatabase();

//   final rows = await db.query(
//     'images',
//     orderBy: 'timestamp DESC',
//   );

//   final results = <SavedImageInfo>[];

//   for (final row in rows) {
//     final imageId = row['id'] as String;
//     final storedPath = row['imagePath'] as String;

//     final resolvedPath = await resolveSavedImagePath(storedPath);

//     if (!await File(resolvedPath).exists()) {
//       await deleteImageRecord(db, imageId);
//       continue;
//     }

//     final colorIds = await loadColorIdsForImage(db, imageId);

//     results.add(
//       SavedImageInfo(
//         id: imageId,
//         imagePath: resolvedPath,
//         colorIds: colorIds,
//         latitude: row['latitude'] as double,
//         longitude: row['longitude'] as double,
//         timestamp: row['timestamp'] as String,
//       ),
//     );
//   }

//   return results;
// }

// Future<List<SavedImageInfo>> getImagesByColorIdSql(int colorId) async {
//   final db = await getAppDatabase();

//   final rows = await db.rawQuery(
//     '''
//     SELECT images.*
//     FROM images
//     JOIN image_colors
//       ON images.id = image_colors.imageId
//     WHERE image_colors.colorId = ?
//     ORDER BY images.timestamp DESC
//     ''',
//     [colorId],
//   );

//   final results = <SavedImageInfo>[];

//   for (final row in rows) {
//     final imageId = row['id'] as String;
//     final storedPath = row['imagePath'] as String;

//     final resolvedPath = await resolveSavedImagePath(storedPath);

//     if (!await File(resolvedPath).exists()) {
//       await deleteImageRecord(db, imageId);
//       continue;
//     }

//     final colorIds = await loadColorIdsForImage(db, imageId);

//     results.add(
//       SavedImageInfo(
//         id: imageId,
//         imagePath: resolvedPath,
//         colorIds: colorIds,
//         latitude: row['latitude'] as double,
//         longitude: row['longitude'] as double,
//         timestamp: row['timestamp'] as String,
//       ),
//     );
//   }

//   return results;
// }

// Future<List<int>> loadColorIdsForImage(Database db, String imageId) async {
//   final colorRows = await db.query(
//     'image_colors',
//     where: 'imageId = ?',
//     whereArgs: [imageId],
//   );

//   return colorRows.map((row) => row['colorId'] as int).toList();
// }

// Future<void> deleteImageRecord(Database db, String imageId) async {
//   await db.delete(
//     'image_colors',
//     where: 'imageId = ?',
//     whereArgs: [imageId],
//   );

//   await db.delete(
//     'images',
//     where: 'id = ?',
//     whereArgs: [imageId],
//   );
// }










// import 'dart:io';
// import 'dart:math';
// import 'dart:typed_data';

// import 'package:opencv_dart/opencv.dart' as cv;
// import 'package:path_provider/path_provider.dart';
// import 'package:sqflite/sqflite.dart';
// import 'package:path/path.dart' as p;

// class ColorRGB {
//   final int r;
//   final int g;
//   final int b;

//   const ColorRGB(this.r, this.g, this.b);

//   @override
//   bool operator ==(Object other) =>
//       identical(this, other) ||
//       other is ColorRGB &&
//           r == other.r &&
//           g == other.g &&
//           b == other.b;

//   @override
//   int get hashCode => Object.hash(r, g, b);
// }

// class ObjectResult {
//   final List<ColorRGB> colors;

//   const ObjectResult({
//     required this.colors,
//   });
// }

// class PaletteColorScore {
//   final ColorRGB color;
//   final double ratio;

//   const PaletteColorScore({
//     required this.color,
//     required this.ratio,
//   });
// }

// List<int> extractColorIdsFromImageBytes(Uint8List imageBytes) {
//   final src = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
//   final result = extractMainColors(src);
//   src.dispose();

//   final colorIds = result.colors
//       .map((color) => colorPalette24.indexOf(color))
//       .where((idx) => idx >= 0)
//       .toList();

//   return colorIds;
// }

// // ====================================================
// // 12色パレット
// // 変数名は既存コード互換のため colorPalette24 のまま
// // ====================================================

// final List<ColorRGB> colorPalette24 = [
//   const ColorRGB(0, 0, 0),        // 0 Black
//   const ColorRGB(100, 100, 100),  // 1 Gray
//   const ColorRGB(255, 255, 255),  // 2 White
//   const ColorRGB(255, 0, 0),      // 3 Red
//   const ColorRGB(255, 105, 180),  // 4 Pink
//   const ColorRGB(255, 128, 0),    // 5 Orange
//   const ColorRGB(255, 255, 0),    // 6 Yellow
//   const ColorRGB(0, 200, 0),      // 7 Green
//   const ColorRGB(0, 192, 255),    // 8 SkyBlue
//   const ColorRGB(0, 0, 255),      // 9 Blue
//   const ColorRGB(128, 0, 255),    // 10 Purple
//   const ColorRGB(139, 69, 19),    // 11 Brown
// ];

// final List<String> colorNames24 = [
//   'Black',
//   'Gray',
//   'White',
//   'Red',
//   'Pink',
//   'Orange',
//   'Yellow',
//   'Green',
//   'SkyBlue',
//   'Blue',
//   'Purple',
//   'Brown',
// ];

// List<String> getColorNamesFromIds(List<int> colorIds) {
//   return colorIds
//       .where((id) => id >= 0 && id < colorNames24.length)
//       .map((id) => colorNames24[id])
//       .toList();
// }

// ColorRGB? getColorFromId(int colorId) {
//   if (colorId < 0 || colorId >= colorPalette24.length) return null;
//   return colorPalette24[colorId];
// }

// // ====================================================
// // 代表色抽出
// // ====================================================

// ObjectResult extractMainColors(cv.Mat src) {
//   final colorSrc = resizeShortSide(src, 128);

//   final colorScores = computePaletteColorRatios(
//     colorSrc,
//     minRatio: 0.08,
//     maxColors: 3,
//   );

//   colorSrc.dispose();

//   if (colorScores.isEmpty) {
//     return const ObjectResult(colors: [ColorRGB(0, 0, 0)]);
//   }

//   return ObjectResult(
//     colors: colorScores.map((score) => score.color).toList(),
//   );
// }

// cv.Mat resizeShortSide(cv.Mat src, int targetShortSide) {
//   final width = src.cols;
//   final height = src.rows;

//   late int newWidth;
//   late int newHeight;

//   if (width <= height) {
//     newWidth = targetShortSide;
//     newHeight = (height * targetShortSide / width).round();
//   } else {
//     newHeight = targetShortSide;
//     newWidth = (width * targetShortSide / height).round();
//   }

//   return cv.resize(
//     src,
//     (newWidth, newHeight),
//     interpolation: cv.INTER_LINEAR,
//   );
// }

// /// 各ピクセルを12色へ分類し、割合が閾値以上の上位色を返す。
// List<PaletteColorScore> computePaletteColorRatios(
//   cv.Mat image, {
//   double minRatio = 0.08,
//   int maxColors = 3,
// }) {
//   final scores = List<double>.filled(colorPalette24.length, 0.0);
//   double totalScore = 0.0;

//   final width = image.cols;
//   final height = image.rows;

//   final cx = (width - 1) / 2.0;
//   final cy = (height - 1) / 2.0;

//   final sx = max(width * 0.45, 1.0);
//   final sy = max(height * 0.45, 1.0);

//   for (int y = 0; y < height; y++) {
//     for (int x = 0; x < width; x++) {
//       final pixel = image.at<cv.Vec3b>(y, x);

//       final b = pixel.val1.toInt();
//       final g = pixel.val2.toInt();
//       final r = pixel.val3.toInt();

//       final colorId = classifyPixelToPaletteId(r, g, b);

//       final dx = (x - cx) / sx;
//       final dy = (y - cy) / sy;

//       // 中央を少し重視。
//       // 端の被写体を消しすぎないように弱めの重み。
//       final centerWeight = 0.80 + 0.20 * exp(-(dx * dx + dy * dy) / 2.0);

//       scores[colorId] += centerWeight;
//       totalScore += centerWeight;
//     }
//   }

//   if (totalScore <= 0) {
//     return [];
//   }

//   final results = <PaletteColorScore>[];

//   for (int i = 0; i < scores.length; i++) {
//     final ratio = scores[i] / totalScore;

//     // 白黒グレーは背景や影で入りやすいので少しだけ厳しめ。
//     final isMonoColor = i == 0 || i == 1 || i == 2;
//     final threshold = isMonoColor ? max(minRatio, 0.16) : minRatio;

//     if (ratio >= threshold) {
//       results.add(
//         PaletteColorScore(
//           color: colorPalette24[i],
//           ratio: ratio,
//         ),
//       );
//     }
//   }

//   results.sort((a, b) => b.ratio.compareTo(a.ratio));

//   if (results.length > maxColors) {
//     return results.sublist(0, maxColors);
//   }

//   return results;
// }

// /// 1ピクセルを12色パレットのIDへ分類する。
// ///
// /// ここを調整すると分類の性格が変わる。
// /// 白・影・ピンク・茶色あたりの誤分類を避けるため、HSVで先に大まかに分ける。
// int classifyPixelToPaletteId(int r, int g, int b) {
//   final hsv = rgbToHsv(r, g, b);
//   final hue = hsv[0];
//   final saturation = hsv[1];
//   final value = hsv[2];

//   // ----------------------------
//   // 低彩度系：白・黒・グレー
//   // ----------------------------

//   // かなり白いものだけWhite
//   // 薄い有彩色がWhiteに吸われにくくする
//   if (saturation < 0.11 && value > 0.72) {
//     return 2; // White
//   }

//   // 黒
//   if (saturation < 0.16 && value < 0.20) {
//     return 0; // Black
//   }

//   // グレー
//   // Grayも条件を少し厳しくする
//   if (saturation < 0.09 && value >= 0.20 && value <= 0.62) {
//     return 1; // Gray
//   }

//   // かなり明るく、彩度が低い場合だけWhite
//   if (value > 0.86 && saturation < 0.16) {
//     return 2; // White
//   }

//   // ----------------------------
//   // 茶色判定
//   // ----------------------------
//   // 暗めの赤〜黄系はOrangeやRedではなくBrownに寄せる
//   if (value < 0.58 && saturation > 0.25 && hue >= 10 && hue < 55) {
//     return 11; // Brown
//   }

//   // ----------------------------
//   // 有彩色：Hueで分類
//   // ----------------------------

//   if (hue < 12 || hue >= 350) {
//     return 3; // Red
//   }

//   if (hue >= 330 && hue < 350) {
//     return 4; // Pink
//   }

//   if (hue >= 12 && hue < 38) {
//     return 5; // Orange
//   }

//   if (hue >= 38 && hue < 68) {
//     return 6; // Yellow
//   }

//   if (hue >= 68 && hue < 165) {
//     return 7; // Green
//   }

//   if (hue >= 165 && hue < 205) {
//     return 8; // SkyBlue
//   }

//   if (hue >= 205 && hue < 255) {
//     return 9; // Blue
//   }

//   if (hue >= 255 && hue < 330) {
//     return 10; // Purple
//   }

//   return 1; // Gray fallback
// }

// // ====================================================
// // 色変換
// // ====================================================

// List<double> rgbToHsv(int r, int g, int b) {
//   final rf = r / 255.0;
//   final gf = g / 255.0;
//   final bf = b / 255.0;

//   final maxC = [rf, gf, bf].reduce(max);
//   final minC = [rf, gf, bf].reduce(min);
//   final delta = maxC - minC;

//   double h = 0.0;

//   if (delta != 0) {
//     if (maxC == rf) {
//       h = 60.0 * (((gf - bf) / delta) % 6.0);
//     } else if (maxC == gf) {
//       h = 60.0 * (((bf - rf) / delta) + 2.0);
//     } else {
//       h = 60.0 * (((rf - gf) / delta) + 4.0);
//     }
//   }

//   if (h < 0) h += 360.0;

//   final s = maxC == 0 ? 0.0 : delta / maxC;
//   final v = maxC;

//   return [h, s, v];
// }

// // ====================================================
// // 永続化 sqflite
// // ====================================================

// class SavedImageInfo {
//   final String id;
//   final String imagePath;
//   final List<int> colorIds;
//   final double latitude;
//   final double longitude;
//   final String timestamp;

//   const SavedImageInfo({
//     required this.id,
//     required this.imagePath,
//     required this.colorIds,
//     required this.latitude,
//     required this.longitude,
//     required this.timestamp,
//   });

//   Map<String, dynamic> toJson() {
//     return {
//       'id': id,
//       'imagePath': imagePath,
//       'colorIds': colorIds,
//       'latitude': latitude,
//       'longitude': longitude,
//       'timestamp': timestamp,
//     };
//   }
// }

// Database? _db;

// Future<Directory> getSavedImagesDirectory() async {
//   final dir = await getApplicationDocumentsDirectory();
//   final imagesDir = Directory(p.join(dir.path, 'images'));

//   if (!await imagesDir.exists()) {
//     await imagesDir.create(recursive: true);
//   }

//   return imagesDir;
// }

// Future<String> resolveSavedImagePath(String storedPath) async {
//   final directFile = File(storedPath);

//   if (storedPath.startsWith('/') && await directFile.exists()) {
//     return storedPath;
//   }

//   final dir = await getApplicationDocumentsDirectory();

//   final relativeFile = File(p.join(dir.path, storedPath));
//   if (await relativeFile.exists()) {
//     return relativeFile.path;
//   }

//   final fallbackFile = File(
//     p.join(dir.path, 'images', p.basename(storedPath)),
//   );

//   if (await fallbackFile.exists()) {
//     return fallbackFile.path;
//   }

//   return relativeFile.path;
// }

// Future<Database> getAppDatabase() async {
//   if (_db != null) return _db!;

//   final dir = await getApplicationDocumentsDirectory();
//   final dbPath = p.join(dir.path, 'color_app.db');

//   _db = await openDatabase(
//     dbPath,
//     version: 1,
//     onCreate: (db, version) async {
//       await db.execute('''
//         CREATE TABLE images (
//           id TEXT PRIMARY KEY,
//           imagePath TEXT NOT NULL,
//           latitude REAL NOT NULL,
//           longitude REAL NOT NULL,
//           timestamp TEXT NOT NULL
//         )
//       ''');

//       await db.execute('''
//         CREATE TABLE image_colors (
//           imageId TEXT NOT NULL,
//           colorId INTEGER NOT NULL,
//           PRIMARY KEY (imageId, colorId),
//           FOREIGN KEY (imageId) REFERENCES images(id) ON DELETE CASCADE
//         )
//       ''');

//       await db.execute('''
//         CREATE INDEX idx_image_colors_colorId
//         ON image_colors(colorId)
//       ''');
//     },
//   );

//   return _db!;
// }

// /// 写真バイト列をアプリDocuments/images内に保存し、代表色とともにDBへ登録する。
// Future<SavedImageInfo> saveImageInfoByColorIdsSql({
//   required Uint8List imageBytes,
//   required List<int> colorIds,
//   required double latitude,
//   required double longitude,
// }) async {
//   final imagesDir = await getSavedImagesDirectory();

//   final now = DateTime.now();
//   final id = '${now.microsecondsSinceEpoch}_${Random().nextInt(999999)}';
//   final timestamp = now.toIso8601String();

//   final fileName = '$id.jpg';
//   final relativeImagePath = p.join('images', fileName);
//   final imageFile = File(p.join(imagesDir.path, fileName));

//   await imageFile.writeAsBytes(imageBytes, flush: true);

//   if (!await imageFile.exists()) {
//     throw Exception('画像ファイルの保存に失敗しました');
//   }

//   final info = SavedImageInfo(
//     id: id,
//     imagePath: imageFile.path,
//     colorIds: colorIds,
//     latitude: latitude,
//     longitude: longitude,
//     timestamp: timestamp,
//   );

//   final db = await getAppDatabase();

//   await db.transaction((txn) async {
//     await txn.insert(
//       'images',
//       {
//         'id': info.id,
//         'imagePath': relativeImagePath,
//         'latitude': info.latitude,
//         'longitude': info.longitude,
//         'timestamp': info.timestamp,
//       },
//       conflictAlgorithm: ConflictAlgorithm.replace,
//     );

//     for (final colorId in colorIds) {
//       await txn.insert(
//         'image_colors',
//         {
//           'imageId': info.id,
//           'colorId': colorId,
//         },
//         conflictAlgorithm: ConflictAlgorithm.ignore,
//       );
//     }
//   });

//   return info;
// }

// /// 撮影バイト列から代表色抽出 → DB保存までを一括実行する。
// Future<SavedImageInfo> extractAndSavePhoto({
//   required Uint8List imageBytes,
//   required double latitude,
//   required double longitude,
// }) async {
//   final src = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
//   final result = extractMainColors(src);
//   src.dispose();

//   final colorIds = result.colors
//       .map((color) => colorPalette24.indexOf(color))
//       .where((idx) => idx >= 0)
//       .toList();

//   return await saveImageInfoByColorIdsSql(
//     imageBytes: imageBytes,
//     colorIds: colorIds,
//     latitude: latitude,
//     longitude: longitude,
//   );
// }

// /// 保存済みの全画像を新しい順で取得する。
// Future<List<SavedImageInfo>> loadAllSavedImagesSql() async {
//   final db = await getAppDatabase();

//   final rows = await db.query(
//     'images',
//     orderBy: 'timestamp DESC',
//   );

//   final results = <SavedImageInfo>[];

//   for (final row in rows) {
//     final imageId = row['id'] as String;
//     final storedPath = row['imagePath'] as String;

//     final resolvedPath = await resolveSavedImagePath(storedPath);

//     if (!await File(resolvedPath).exists()) {
//       await deleteImageRecord(db, imageId);
//       continue;
//     }

//     final colorIds = await loadColorIdsForImage(db, imageId);

//     results.add(
//       SavedImageInfo(
//         id: imageId,
//         imagePath: resolvedPath,
//         colorIds: colorIds,
//         latitude: row['latitude'] as double,
//         longitude: row['longitude'] as double,
//         timestamp: row['timestamp'] as String,
//       ),
//     );
//   }

//   return results;
// }

// Future<List<SavedImageInfo>> getImagesByColorIdSql(int colorId) async {
//   final db = await getAppDatabase();

//   final rows = await db.rawQuery(
//     '''
//     SELECT images.*
//     FROM images
//     JOIN image_colors
//       ON images.id = image_colors.imageId
//     WHERE image_colors.colorId = ?
//     ORDER BY images.timestamp DESC
//     ''',
//     [colorId],
//   );

//   final results = <SavedImageInfo>[];

//   for (final row in rows) {
//     final imageId = row['id'] as String;
//     final storedPath = row['imagePath'] as String;

//     final resolvedPath = await resolveSavedImagePath(storedPath);

//     if (!await File(resolvedPath).exists()) {
//       await deleteImageRecord(db, imageId);
//       continue;
//     }

//     final colorIds = await loadColorIdsForImage(db, imageId);

//     results.add(
//       SavedImageInfo(
//         id: imageId,
//         imagePath: resolvedPath,
//         colorIds: colorIds,
//         latitude: row['latitude'] as double,
//         longitude: row['longitude'] as double,
//         timestamp: row['timestamp'] as String,
//       ),
//     );
//   }

//   return results;
// }

// Future<List<int>> loadColorIdsForImage(Database db, String imageId) async {
//   final colorRows = await db.query(
//     'image_colors',
//     where: 'imageId = ?',
//     whereArgs: [imageId],
//   );

//   return colorRows.map((row) => row['colorId'] as int).toList();
// }

// Future<void> deleteImageRecord(Database db, String imageId) async {
//   await db.delete(
//     'image_colors',
//     where: 'imageId = ?',
//     whereArgs: [imageId],
//   );

//   await db.delete(
//     'images',
//     where: 'id = ?',
//     whereArgs: [imageId],
//   );
// }

// // 写真の削除
// Future<void> deleteSavedImageByIdSql(String imageId) async {
//   final db = await getAppDatabase();

//   final rows = await db.query(
//     'images',
//     where: 'id = ?',
//     whereArgs: [imageId],
//     limit: 1,
//   );

//   if (rows.isEmpty) return;

//   final storedPath = rows.first['imagePath'] as String;
//   final resolvedPath = await resolveSavedImagePath(storedPath);

//   final file = File(resolvedPath);
//   if (await file.exists()) {
//     await file.delete();
//   }

//   await db.delete(
//     'image_colors',
//     where: 'imageId = ?',
//     whereArgs: [imageId],
//   );

//   await db.delete(
//     'images',
//     where: 'id = ?',
//     whereArgs: [imageId],
//   );
// }