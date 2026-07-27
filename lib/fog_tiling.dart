import 'dart:math' as math;

import 'package:flutter/painting.dart' show Size;
import 'package:latlong2/latlong.dart';

/// 雲テクスチャを地図へ貼り付けるための、タイルの大きさと位置。
class FogTilePlacement {
  /// 雲 1 枚の表示サイズ（画面ピクセル）
  final double tileSizePx;

  /// テクスチャ原点の画面座標
  final double offsetX;
  final double offsetY;

  const FogTilePlacement({
    required this.tileSizePx,
    required this.offsetX,
    required this.offsetY,
  });
}

/// 雲タイルの配置計算。
///
/// ── なぜ専用の計算が必要か ──
/// 素朴に「赤道原点(0,0)の画面座標」を基準にすると、その値はズーム 15 で
/// 数百万ピクセルという巨大な数になる。GPU のシェーダ行列は float32 なので
/// そのままでは精度が足りず、タイルの周期で剰余を取って小さくする必要がある。
///
/// ところが周期を「画面中心の緯度から求めたメートル/ピクセル」で計算すると、
/// 地図を南北に動かすたびに周期がごくわずかに変わり、
/// 巨大な値の剰余がその何千倍にも増幅されて跳ねる（＝雲がガクッとずれる）。
///
/// そこで、
///   * タイル格子を「ズーム 0 の投影座標（0〜256）」という
///     ズームにも緯度にも依存しない空間で定義する
///   * 画面中心のすぐ近くにある格子点を基準にする
/// という方式にした。扱う数が小さいので増幅が起きず、
/// パンでもピンチでも雲が地図に貼り付いたまま滑らかに動く。
class FogTiling {
  FogTiling._();

  /// 赤道の全周（メートル）。Web メルカトルの基準。
  static const double _earthCircumference = 40075016.686;

  /// ズーム 0 でのワールドサイズ（タイル 256px 前提）。
  static const double _worldSizeAtZoom0 = 256.0;

  /// 雲タイルの配置を求める。
  ///
  /// [tileMeters] は赤道上での 1 枚あたりの実距離。メルカトル図法では
  /// 高緯度ほど地図自体が引き伸ばされるため、緯度補正はあえて掛けない
  /// （掛けると「地図に貼り付いている」挙動から外れる）。
  ///
  /// [mirrored] が true のとき、タイルは鏡張りで 2 枚 1 周期になる。
  static FogTilePlacement compute({
    required double zoom,
    required LatLng center,
    required Size size,
    required double tileMeters,
    bool mirrored = true,
  }) {
    final scale = math.pow(2.0, zoom).toDouble();

    // ズーム 0 でのタイルの大きさ（定数。ズームにも緯度にも依存しない）
    final tile0 = tileMeters * _worldSizeAtZoom0 / _earthCircumference;
    final period0 = mirrored ? tile0 * 2 : tile0;

    if (tile0 <= 0 || !tile0.isFinite) {
      return FogTilePlacement(tileSizePx: 0, offsetX: 0, offsetY: 0);
    }

    // 画面中心のズーム 0 投影座標
    final c0 = _project(center);

    // 中心のすぐ手前にある格子点（ここを基準にすることで数を小さく保つ）
    final gx0 = (c0.dx / period0).floorToDouble() * period0;
    final gy0 = (c0.dy / period0).floorToDouble() * period0;

    // 格子点は中心から見て period0 未満のずれ → 画面座標へ変換しても小さい
    final offsetX = size.width / 2 + (gx0 - c0.dx) * scale;
    final offsetY = size.height / 2 + (gy0 - c0.dy) * scale;

    return FogTilePlacement(
      tileSizePx: tile0 * scale,
      offsetX: offsetX,
      offsetY: offsetY,
    );
  }

  /// 緯度経度 → ズーム 0 の Web メルカトル座標（0〜256）。
  static _Point _project(LatLng p) {
    final lat = p.latitude.clamp(-85.05112878, 85.05112878);
    final x = (p.longitude + 180.0) / 360.0 * _worldSizeAtZoom0;
    final sinLat = math.sin(lat * math.pi / 180.0);
    final y = (0.5 -
            math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) *
        _worldSizeAtZoom0;
    return _Point(x, y);
  }
}

class _Point {
  final double dx;
  final double dy;
  const _Point(this.dx, this.dy);
}
