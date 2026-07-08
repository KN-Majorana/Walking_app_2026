import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:opencv_dart/opencv.dart' as cv;

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
// 24色パレット（無彩色なし）
// ─────────────────────────────────────────

final List<ColorRGB> colorPalette24 = [
  const ColorRGB(255, 0, 0),      //  0  Red
  const ColorRGB(192, 0, 0),      //  1  DarkRed
  // Pink    → Red / LightOrange に吸収
  const ColorRGB(255, 128, 0),    //  2  Orange
  const ColorRGB(255, 192, 0),    //  3  Amber
  const ColorRGB(255, 255, 0),    //  4  Yellow
  const ColorRGB(192, 255, 0),    //  5  YellowGreen
  const ColorRGB(128, 255, 0),    //  6  Lime
  const ColorRGB(0, 200, 0),      //  7  Green
  // DarkGreen → Green に吸収
  const ColorRGB(0, 255, 255),    //  8  Cyan
  const ColorRGB(0, 192, 255),    //  9  SkyBlue
  const ColorRGB(0, 0, 255),      // 10  Blue
  const ColorRGB(0, 0, 128),      // 11  Navy
  const ColorRGB(128, 0, 255),    // 12  Purple
  const ColorRGB(255, 0, 255),    // 13  Magenta
  // const ColorRGB(255, 220, 177),  // 14  LightOrange
];

final List<String> colorNames24 = [
  'Red', 'DarkRed',
  'Orange', 'Amber', 'Yellow', 'YellowGreen', 'Lime',
  'Green',
  'Cyan', 'SkyBlue', 'Blue', 'Navy',
  'Purple', 'Magenta',
];

// ─────────────────────────────────────────
// パレットの Lab 値をキャッシュ（起動時に1回だけ計算）
// ─────────────────────────────────────────

final List<List<double>> _paletteLab =
    colorPalette24.map((c) => _rgbToLab(c.r, c.g, c.b)).toList();

// ─────────────────────────────────────────
// 公開 API
// ─────────────────────────────────────────

/// ファイルパスから主要色のパレットインデックスリストを返す。
Future<List<int>> extractColorIdsFromPath(String imagePath) async {
  try {
    final bytes = await File(imagePath).readAsBytes();
    return extractColorIdsFromBytes(bytes);
  } catch (_) {
    return [];
  }
}

/// 画像バイト列から主要色のパレットインデックスリストを返す。
List<int> extractColorIdsFromBytes(Uint8List bytes) {
  final src = cv.imdecode(bytes, cv.IMREAD_COLOR);
  try {
    final result = extractMainColors(src);
    return result.colors
        .map((c) => colorPalette24.indexOf(c))
        .where((idx) => idx >= 0)
        .toList();
  } finally {
    src.dispose();
  }
}

/// cv.Mat から主要色を抽出する。
///
/// アルゴリズム:
///   1. 短辺 128px にリサイズ
///   2. 中央 [centerRatio] 領域をクロップ（端の背景色を除外）
///   3. 各ピクセルを Lab 空間でパレット色へ直接マッピング
///   4. ガウス重み（中心ほど高い）で投票
///   5. 得票率 20% 以上の色を最大 3 色返す → 最頻値ベース（彩度フィルタ済み）
ObjectResult extractMainColors(cv.Mat src, {double centerRatio = 0.5}) {
  // パレット Lab 値を初期化（初回のみ）
  _paletteLab; // access to trigger late init

  final resized = resizeShortSide(src, 128);
  final cropped = _cropCenter(resized, centerRatio);

  final votes = _weightedPaletteVote(cropped);

  resized.dispose(); // cropped は resized のビューなので個別 dispose 不要

  if (votes.isEmpty) return const ObjectResult(colors: []);

  final total = votes.values.fold(0.0, (a, b) => a + b);
  final sorted = votes.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  // 得票率 20% 以上の色を最大 3 色返す（ノイズ排除のため閾値高め）
  const minRatio = 0.20;
  const maxColors = 3;
  final result = <ColorRGB>[];
  for (final e in sorted) {
    if (result.length >= maxColors) break;
    if (e.value / total >= minRatio) {
      result.add(colorPalette24[e.key]);
    }
  }

  // 閾値を超える色がない場合でも最多得票色は必ず返す
  if (result.isEmpty) result.add(colorPalette24[sorted.first.key]);

  return ObjectResult(colors: result);
}

// ─────────────────────────────────────────
// 内部: 重み付きパレット投票
// ─────────────────────────────────────────

/// 各ピクセルをガウス重み付きで直接パレット色へ投票させる。
///
/// - 中心に近いピクセルほど強く影響（sigma = 0.4）
/// - 彩度 [minSaturation] 未満のピクセル（白・灰・黒）はスキップ
/// - 投票ウェイト = ガウス重み × 彩度（鮮やかなほど強く票入れ）
Map<int, double> _weightedPaletteVote(cv.Mat image) {
  final Map<int, double> votes = {};

  final w = image.cols;
  final h = image.rows;
  final cx = (w - 1) / 2.0;
  final cy = (h - 1) / 2.0;

  const sigma = 0.4;
  const invSigma2x2 = 1.0 / (2.0 * sigma * sigma);

  // 低彩度ピクセルは除外（無彩色は色識別に寄与しない）
  const minSaturation = 0.18;

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final p = image.at<cv.Vec3b>(y, x);
      final b = p.val1.toInt();
      final g = p.val2.toInt();
      final r = p.val3.toInt();

      // 彩度フィルタ（低彩度はスキップ）
      final sat = _saturation(r, g, b);
      if (sat < minSaturation) continue;

      // ガウス重み × 彩度（鮮やかなほど強く投票）
      final dx = (x - cx) / cx;
      final dy = (y - cy) / cy;
      final gaussWeight = exp(-(dx * dx + dy * dy) * invSigma2x2);
      final weight = gaussWeight * sat;

      final idx = _nearestPaletteIdx(r, g, b);
      votes[idx] = (votes[idx] ?? 0.0) + weight;
    }
  }

  return votes;
}

/// HSV 彩度（0.0〜1.0）を純 Dart で計算
double _saturation(int r, int g, int b) {
  final maxC = max(r, max(g, b));
  final minC = min(r, min(g, b));
  return maxC == 0 ? 0.0 : (maxC - minC) / maxC.toDouble();
}

/// RGB → 最近傍パレットインデックス（Lab 空間、純 Dart 計算）
int _nearestPaletteIdx(int r, int g, int b) {
  final lab = _rgbToLab(r, g, b);
  int best = 0;
  double bestDist = double.infinity;

  for (int i = 0; i < _paletteLab.length; i++) {
    final pl = _paletteLab[i];
    final dL = lab[0] - pl[0];
    final da = lab[1] - pl[1];
    final db = lab[2] - pl[2];
    final dist = dL * dL + da * da + db * db;
    if (dist < bestDist) {
      bestDist = dist;
      best = i;
    }
  }

  return best;
}

// ─────────────────────────────────────────
// 色空間変換（純 Dart）
// ─────────────────────────────────────────

/// RGB → CIE L*a*b*（D65 白色点）
List<double> _rgbToLab(int r, int g, int b) {
  // 1. sRGB → 線形 RGB
  double lin(int c) {
    final v = c / 255.0;
    return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  final lr = lin(r);
  final lg = lin(g);
  final lb = lin(b);

  // 2. 線形 RGB → XYZ (D65)
  final x = lr * 0.4124564 + lg * 0.3575761 + lb * 0.1804375;
  final y = lr * 0.2126729 + lg * 0.7151522 + lb * 0.0721750;
  final z = lr * 0.0193339 + lg * 0.1191920 + lb * 0.9503041;

  // 3. XYZ → Lab
  double f(double t) =>
      t > 0.008856 ? pow(t, 1.0 / 3.0).toDouble() : 7.787 * t + 16.0 / 116.0;

  final fx = f(x / 0.95047);
  final fy = f(y / 1.00000);
  final fz = f(z / 1.08883);

  return [116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz)];
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

cv.Mat _cropCenter(cv.Mat src, double ratio) {
  final w = src.cols;
  final h = src.rows;
  final cropW = (w * ratio).round().clamp(1, w);
  final cropH = (h * ratio).round().clamp(1, h);
  final x = ((w - cropW) / 2).round();
  final y = ((h - cropH) / 2).round();
  return src.region(cv.Rect(x, y, cropW, cropH));
}

// ─────────────────────────────────────────
// 後方互換（fog_overlay 等から呼ばれる可能性があるので残す）
// ─────────────────────────────────────────

ColorRGB findNearestPaletteColorLab(ColorRGB color) {
  return colorPalette24[_nearestPaletteIdx(color.r, color.g, color.b)];
}
