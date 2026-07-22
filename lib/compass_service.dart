import 'dart:async';

import 'package:flutter_compass/flutter_compass.dart';

/// 端末がどちらを向いているか（磁気コンパスの方位）を配信するサービス。
///
/// 値は真北を 0 度とし、時計回りに 0〜360 度。
/// センサーが無い端末やキャリブレーション前は null が流れることがあるため、
/// 購読側は null を「向き不明」として扱うこと。
class CompassService {
  CompassService._();

  /// 方位のストリーム。値が細かく揺れるので、
  /// 一定角度以上変わったときだけ流して再描画を減らす。
  static Stream<double?> heading({double minChangeDegrees = 1.0}) {
    final source = FlutterCompass.events;
    if (source == null) return const Stream<double?>.empty();

    double? last;
    return source
        .map((e) => e.heading)
        .where((h) {
          if (h == null) return false;
          if (last == null) {
            last = h;
            return true;
          }
          // 359度→1度のように一周をまたぐ変化も正しく扱う
          final diff = _angleDiff(h, last!).abs();
          if (diff < minChangeDegrees) return false;
          last = h;
          return true;
        })
        .cast<double?>();
  }

  /// 2 つの方位の差を -180〜180 度に正規化する。
  static double _angleDiff(double a, double b) {
    var d = (a - b) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }
}
