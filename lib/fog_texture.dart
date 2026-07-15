import 'dart:math';
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

  /// 柔らかい雲のようなテクスチャをプロシージャル生成する。
  static Future<ui.Image> _generateProcedural({int size = 1024}) async {
    final recorder = ui.PictureRecorder();
    final rect = ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
    final canvas = ui.Canvas(recorder, rect);

    // ベース: うっすら青みがかった明るいグレー（霧のベース色）
    canvas.drawRect(rect, ui.Paint()..color = const ui.Color(0xE6C9CDD3));

    final rnd = Random(7);
    // 明るい雲と少し暗い雲を多数重ねて、もこもこした質感を作る。
    for (int i = 0; i < 520; i++) {
      final x = rnd.nextDouble() * size;
      final y = rnd.nextDouble() * size;
      final r = size * (0.03 + rnd.nextDouble() * 0.15);
      final bright = rnd.nextDouble() < 0.6;
      final v = bright ? 230 + rnd.nextInt(25) : 150 + rnd.nextInt(45);
      final a = 0.04 + rnd.nextDouble() * 0.16;
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
