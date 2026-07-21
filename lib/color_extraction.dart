import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:opencv_dart/opencv.dart' as cv;

// ============================================================
// 色判定ロジック（integration_Ver1 唯一の色判定ファイル）
//
// このファイルは全モード（散歩／霧／再生／コラージュなどの通常モードと、
// 対戦モード battle/* の両方）から import される、プロジェクト内で唯一の
// 色判定実装。以前は lib/color_extraction.dart と lib/battle/color_extraction.dart
// の2つに分かれていたが、このファイル1つに統合した。
//
// 判定アルゴリズムは現行 Battle_Function_Ver2（＝Demotest 準拠）に統一:
//   - RGB to Lab 変換: OpenCV cv.cvtColor(BGR2Lab) を使用
//   - 最近傍: a-b 平面の「色相角 to 彩度」極座標マッチング
//   - 投票:   彩度は一切見ず、全ピクセルをガウス重みだけで集計
//   - minRatio: 0.10
//
// 色候補（colorPalette24 / colorNames24）は Demotest のもの（無彩色ありの12色）。
// ※ colorId は各種保存データ（Firestore の対戦色、ローカルの写真ピン色など）の
//   index を参照するため、パレット変更に伴い既存データの色意味がずれる点に注意。
// ============================================================

// ─────────────────────────────────────────
// モデル
// ─────────────────────────────────────────

class ColorRGB {
  final int r;
  final int g;
  final int b;

  const ColorRGB(this.r, this.g, this.b);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorRGB && r == other.r && g == other.g && b == other.b;

  @override
  int get hashCode => Object.hash(r, g, b);
}

class ObjectResult {
  final List<ColorRGB> colors;
  const ObjectResult({required this.colors});
}

// ─────────────────────────────────────────
// 色候補パレット（Demotest 準拠：無彩色ありの12色）
//   ※ 変数名は歴史的経緯で colorPalette24 だが要素数は12。
//   ※ index が colorId（保存データ）と対応する。
// ─────────────────────────────────────────

final List<ColorRGB> colorPalette24 = [
  const ColorRGB(0, 0, 0),        //  0  Black
  const ColorRGB(255, 255, 255),  //  1  White
  const ColorRGB(255, 0, 0),      //  2  Red
  const ColorRGB(255, 192, 203),  //  3  Pink
  const ColorRGB(255, 128, 0),    //  4  Orange
  const ColorRGB(255, 255, 0),    //  5  Yellow
  const ColorRGB(0, 200, 0),      //  6  Green
  const ColorRGB(0, 255, 255),    //  7  Cyan
  const ColorRGB(0, 192, 255),    //  8  SkyBlue
  const ColorRGB(0, 0, 255),      //  9  Blue
  const ColorRGB(255, 0, 255),    // 10  Purple
  const ColorRGB(139, 69, 19),    // 11  Brown
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

// ─────────────────────────────────────────
// 対戦モード専用の色候補（Demotest の色候補から Black / White / Brown を除いた9色）
//   通常モードは上の colorPalette24（Demotest 12色）を使い、
//   対戦モードだけこの colorPaletteBattle / colorNamesBattle を使う。
//   ※ index が対戦の colorId（Firestore 保存）と対応する。
//   ※ 旧14色パレットから並びが変わったため、既存 Firestore データは
//     colorId のマイグレーションが必要（別途スクリプトで remap）。
// ─────────────────────────────────────────

final List<ColorRGB> colorPaletteBattle = [
  const ColorRGB(255, 0, 0),      //  0  Red
  const ColorRGB(255, 192, 203),  //  1  Pink
  const ColorRGB(255, 128, 0),    //  2  Orange
  const ColorRGB(255, 255, 0),    //  3  Yellow
  const ColorRGB(0, 200, 0),      //  4  Green
  const ColorRGB(0, 255, 255),    //  5  Cyan
  const ColorRGB(0, 192, 255),    //  6  SkyBlue
  const ColorRGB(0, 0, 255),      //  7  Blue
  const ColorRGB(255, 0, 255),    //  8  Purple
];

final List<String> colorNamesBattle = [
  'Red',
  'Pink',
  'Orange',
  'Yellow',
  'Green',
  'Cyan',
  'SkyBlue',
  'Blue',
  'Purple',
];

// ─────────────────────────────────────────
// 公開エントリポイント
// ─────────────────────────────────────────

/// ファイルパスから主要色のパレットインデックスリストを返す。
/// [palette] を省略すると通常モードの colorPalette24（Demotest 12色）を使う。
/// 対戦モードは palette: colorPaletteBattle を渡すこと。
Future<List<int>> extractColorIdsFromPath(
  String imagePath, {
  List<ColorRGB>? palette,
}) async {
  try {
    final bytes = await File(imagePath).readAsBytes();
    return extractColorIdsFromBytes(bytes, palette: palette);
  } catch (_) {
    return [];
  }
}

/// 画像バイト列から主要色のパレットインデックスリストを返す。
List<int> extractColorIdsFromBytes(
  Uint8List bytes, {
  List<ColorRGB>? palette,
}) {
  final pal = palette ?? colorPalette24;
  final src = cv.imdecode(bytes, cv.IMREAD_COLOR);
  try {
    final result = extractMainColors(src, palette: pal);
    return result.colors
        .map((c) => pal.indexOf(c))
        .where((idx) => idx >= 0)
        .toList();
  } finally {
    src.dispose();
  }
}

/// cv.Mat から主要色を抽出する。
///
/// アルゴリズム（Demotest 準拠）:
///   1. 短辺 128px にリサイズ
///   2. 全ピクセルをガウス中心重みだけで投票（彩度フィルタなし・クロップなし）
///   3. 各ピクセルを Lab の色相角 to 彩度で最近傍パレット色へ割り当て
///   4. 得票率 10% 以上の色を最大 3 色返す（0色なら最多得票色を 1 色返す）
ObjectResult extractMainColors(cv.Mat src, {List<ColorRGB>? palette}) {
  final colorSrc = resizeShortSide(src, 128);

  final paletteColors = computePaletteColorsByPixelVoting(
    colorSrc,
    minRatio: 0.10,
    topK: 3,
    palette: palette ?? colorPalette24,
  );

  colorSrc.dispose();

  return ObjectResult(colors: paletteColors);
}

// ─────────────────────────────────────────
// 投票（Demotest 準拠：彩度を一切見ず、全ピクセルをガウス重みだけで集計）
// ─────────────────────────────────────────

List<ColorRGB> computePaletteColorsByPixelVoting(
  cv.Mat image, {
  double minRatio = 0.10,
  int topK = 3,
  List<ColorRGB>? palette,
}) {
  final pal = palette ?? colorPalette24;
  final Map<ColorRGB, double> scores = {};

  final width = image.cols;
  final height = image.rows;

  final cx = (width - 1) / 2.0;
  final cy = (height - 1) / 2.0;

  // 中心重みの強さ（小さいほど中心重視、大きいほど全体を均等に見る）
  const sigma = 0.45;
  const invSigma2x2 = 1.0 / (2.0 * sigma * sigma);

  double totalScore = 0.0;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final p = image.at<cv.Vec3b>(y, x);

      final b = p.val1.toInt();
      final g = p.val2.toInt();
      final r = p.val3.toInt();

      // 中心ほどスコアを高くするガウス重み（彩度は一切見ない）
      final dx = cx == 0 ? 0.0 : (x - cx) / cx;
      final dy = cy == 0 ? 0.0 : (y - cy) / cy;
      final centerWeight = exp(
        -(dx * dx + dy * dy) * invSigma2x2,
      );

      final color = ColorRGB(r, g, b);
      final paletteColor = findNearestPaletteColorLab(color, palette: pal);

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

  // 閾値以上がない場合でも、最低1色は返す
  if (result.isEmpty) {
    result.add(sorted.first.key);
  }

  return result;
}

// ─────────────────────────────────────────
// 最近傍（Demotest 準拠：a-b 平面の色相角 to 彩度で最近傍を選ぶ）
// ─────────────────────────────────────────

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

ColorRGB findNearestPaletteColorLab(ColorRGB color, {List<ColorRGB>? palette}) {
  final pal = palette ?? colorPalette24;
  final inputLab = rgbToLabColor(color);

  // OpenCV Lab は a,b が 128 中心なので 0 中心に直す
  final inputA = inputLab[1] - 128.0;
  final inputB = inputLab[2] - 128.0;

  // ab 平面上で中心からの距離（彩度）
  final inputChroma = sqrt(inputA * inputA + inputB * inputB);

  // 中心にかなり近い（＝ほぼ無彩色の）色は色相角が不安定。
  // Lab 全成分のユークリッド距離で最も近いパレット色へフォールバックする。
  // 通常モードのパレットには Black/White があるため無彩色ピクセルは明度の近い
  // Black/White へ、対戦モードのパレットは無彩色なしのため最寄りの有彩色へ寄る。
  const neutralChromaThreshold = 10.0;

  if (inputChroma < neutralChromaThreshold) {
    return _nearestPaletteColorByLabDistance(color, pal);
  }

  final inputHue = atan2(inputB, inputA);

  final candidates = <_PaletteCandidate>[];

  for (final p in pal) {
    final paletteLab = rgbToLabColor(p);

    final paletteA = paletteLab[1] - 128.0;
    final paletteB = paletteLab[2] - 128.0;

    final paletteChroma = sqrt(
      paletteA * paletteA + paletteB * paletteB,
    );

    // 無彩色パレット（Black/White）は有彩色候補から除外
    if (paletteChroma < neutralChromaThreshold) {
      continue;
    }

    final paletteHue = atan2(paletteB, paletteA);

    // まず色相角の差で大まかに分類
    final hueDiff = _angleDiff(inputHue, paletteHue);

    // 次に中心からの距離（彩度）の近さで分類
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
    return _nearestPaletteColorByLabDistance(color, pal);
  }

  // まず ab 平面の角度が近い順に並べる
  candidates.sort((a, b) => a.hueDiff.compareTo(b.hueDiff));

  final bestHueDiff = candidates.first.hueDiff;

  // 一番近い角度から、どこまでを「同じ方向の色」とみなすか
  //   0.25 rad ≒ 14.3 度
  const hueMargin = 0.25;

  final hueCandidates = candidates
      .where((c) => c.hueDiff <= bestHueDiff + hueMargin)
      .toList();

  // 角度が近い候補の中で、中心からの距離が近い色を選ぶ
  hueCandidates.sort((a, b) {
    final cmpChroma = a.chromaDiff.compareTo(b.chromaDiff);
    if (cmpChroma != 0) return cmpChroma;
    // chroma 差が同じくらいなら、角度が近い方を優先
    return a.hueDiff.compareTo(b.hueDiff);
  });

  return hueCandidates.first.color;
}

/// Lab 全成分のユークリッド二乗距離で最近傍パレット色を選ぶ。
/// （無彩色入力のフォールバック用。Black/White もここで拾われる）
ColorRGB _nearestPaletteColorByLabDistance(
  ColorRGB color, [
  List<ColorRGB>? palette,
]) {
  final pal = palette ?? colorPalette24;
  final inputLab = rgbToLabColor(color);

  ColorRGB nearest = pal.first;
  double minDist = double.infinity;

  for (final p in pal) {
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

// ─────────────────────────────────────────
// RGB to Lab 変換（Demotest 準拠：OpenCV cv.cvtColor を使用）
//   返り値は OpenCV 8bit Lab（L:0-255, a/b:128 中心）
// ─────────────────────────────────────────

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

// ─────────────────────────────────────────
// 画像ユーティリティ
// ─────────────────────────────────────────

cv.Mat resizeShortSide(cv.Mat src, int targetShortSide) {
  final w = src.cols;
  final h = src.rows;
  final int newW, newH;

  if (w <= h) {
    newW = targetShortSide;
    newH = (h * targetShortSide / w).round();
  } else {
    newH = targetShortSide;
    newW = (w * targetShortSide / h).round();
  }

  return cv.resize(src, (newW, newH), interpolation: cv.INTER_LINEAR);
}
