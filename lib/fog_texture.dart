import 'dart:math';
import 'dart:typed_data' show Float64List;
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

/// 霧（フォグ・オブ・ウォー）に使う「雲テクスチャ」を用意するヘルパー。
///
/// 優先順位:
///   1. `assets/fog/fog.png` があればそれを雲テクスチャとして使う
///      （リアルな雲画像を差し替えたいときはここに置く）。
///   2. 無ければ、起動時にプロシージャルで柔らかい雲テクスチャを生成する。
///
/// 生成結果は [image] にキャッシュされ、フォグの CustomPainter から
/// 同期的に参照される。`main()` で [load] を await しておくこと。
class FogTexture {
  FogTexture._();

  static ui.Image? _cached;

  /// 生成済みの雲テクスチャ（未ロードなら null）。
  static ui.Image? get image => _cached;

  /// テクスチャを用意する（アセット優先、無ければプロシージャル生成）。
  static Future<ui.Image> load() async {
    if (_cached != null) return _cached!;
    try {
      final data = await rootBundle.load('assets/fog/fog.png');
      final codec =
          await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _cached = frame.image;
    } catch (_) {
      _cached = await _generateProcedural();
    }
    return _cached!;
  }

  /// 雲テクスチャ 1 枚が覆う実距離（メートル）。
  ///
  /// 地図に対して固定の大きさで貼るため、拡大すると雲も大きく、
  /// 縮小すると雲も細かくなる。既定の縮尺（画面幅 1.5km）でちょうど
  /// 1 枚が画面幅に収まる大きさにしてある。
  static const double tileMeters = 1500.0;

  /// 雲テクスチャを地図に貼り付けて [bounds] を塗る。
  ///
  /// [tileSizePx] は雲 1 枚の表示サイズ（ピクセル）、
  /// [offsetX] / [offsetY] は地図の位置に対応するタイルのずれ。
  /// これらを地図のズーム・中心から計算して渡すことで、
  /// 雲が地図と一緒に拡大縮小・移動する。
  ///
  /// タイルは鏡張り（[ui.TileMode.mirror]）で並べるため、
  /// シームレスでない画像でも継ぎ目が目立たない。
  static void paintWorldTiles(
    ui.Canvas canvas,
    ui.Rect bounds, {
    required double tileSizePx,
    required double offsetX,
    required double offsetY,
    ui.Color fallbackColor = const ui.Color(0xFFF4F6F9),
  }) {
    final tex = _cached;
    if (tex == null || tileSizePx <= 0) {
      canvas.drawRect(bounds, ui.Paint()..color = fallbackColor);
      return;
    }

    final scale = tileSizePx / tex.width;

    // 4x4 の変換行列（列優先）。拡大とずれだけを設定する。
    // GPU 側は float32 精度なので、offset は呼び出し側で
    // 小さい値に丸めてから渡すこと（そうしないと座標が飛ぶ）。
    final matrix = Float64List.fromList(<double>[
      scale, 0, 0, 0, //
      0, scale, 0, 0, //
      0, 0, 1, 0, //
      offsetX, offsetY, 0, 1, //
    ]);

    final shader = ui.ImageShader(
      tex,
      ui.TileMode.mirror,
      ui.TileMode.mirror,
      matrix,
      filterQuality: ui.FilterQuality.medium,
    );

    canvas.drawRect(bounds, ui.Paint()..shader = shader);
  }

  /// 柔らかい雲のようなテクスチャをプロシージャル生成する。
  static Future<ui.Image> _generateProcedural({int size = 1024}) async {
    final recorder = ui.PictureRecorder();
    final rect = ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
    final canvas = ui.Canvas(recorder, rect);

    // ベース: ほぼ白い不透明の雲。霧が晴れていない場所は白く見える。
    canvas.drawRect(rect, ui.Paint()..color = const ui.Color(0xFFF4F6F9));

    final rnd = Random(7);
    // 白と、ごく淡いグレーの陰影を重ねて、もこもこした雲の質感を作る。
    for (int i = 0; i < 520; i++) {
      final x = rnd.nextDouble() * size;
      final y = rnd.nextDouble() * size;
      final r = size * (0.03 + rnd.nextDouble() * 0.15);
      final bright = rnd.nextDouble() < 0.7;
      final v = bright ? 255 : 214 + rnd.nextInt(24);
      final a = 0.05 + rnd.nextDouble() * 0.18;
      canvas.drawCircle(
        ui.Offset(x, y),
        r,
        ui.Paint()
          ..color = ui.Color.fromRGBO(v, v, v, a)
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, r * 0.7),
      );
    }

    final picture = recorder.endRecording();
    return picture.toImage(size, size);
  }
}
