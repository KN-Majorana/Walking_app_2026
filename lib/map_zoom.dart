import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 地図の初期ズームを「画面の横幅が実空間で何メートルに相当するか」から
/// 逆算するユーティリティ。
///
/// flutter_map の既定 CRS（Web メルカトル / 256px タイル）では
///   metersPerPixel = 156543.03392 * cos(latitude) / 2^zoom
/// が成り立つ。これを zoom について解くと
///   zoom = log2(156543.03392 * cos(latitude) * widthPx / spanMeters)
/// になる。端末幅が違っても「端から端まで約 spanMeters」に揃う。
class MapZoom {
  MapZoom._();

  /// 赤道上・ズーム 0 における 1 ピクセルあたりのメートル数。
  static const double _metersPerPixelAtZoom0 = 156543.03392;

  /// 画面の端から端までが [spanMeters] になるズームレベル。
  ///
  /// [widthPx] は論理ピクセル（MediaQuery の width）。
  static double forSpan({
    required double widthPx,
    required double latitude,
    double spanMeters = 1500,
    double minZoom = 3,
    double maxZoom = 19,
  }) {
    if (widthPx <= 0 || spanMeters <= 0) return 15;
    final latRad = latitude * math.pi / 180;
    // 極付近で cos が 0 に近づくと発散するのでクランプする。
    final cosLat = math.cos(latRad).abs().clamp(0.01, 1.0);
    final zoom = _log2(_metersPerPixelAtZoom0 * cosLat * widthPx / spanMeters);
    return zoom.clamp(minZoom, maxZoom);
  }

  /// [context] の画面幅を使って [forSpan] を計算する。
  static double forSpanOf(
    BuildContext context, {
    required double latitude,
    double spanMeters = 3000,
  }) {
    final width = MediaQuery.of(context).size.width;
    return forSpan(widthPx: width, latitude: latitude, spanMeters: spanMeters);
  }

  static double _log2(double x) => math.log(x) / math.ln2;
}

/// アプリ全体で使う既定の表示範囲（画面の端から端まで＝約 3km）。
const double kDefaultMapSpanMeters = 3000;
