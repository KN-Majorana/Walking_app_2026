import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';

// ─────────────────────────────────────────
// Stories レイアウト定義（9:16・インスタのストーリー風）
// スロット: [left%, top%, width%, height%]
// ─────────────────────────────────────────

const _storiesLayouts = <int, List<List<double>>>{
  1: [
    [0.00, 0.00, 1.00, 1.00],
  ],
  2: [
    [0.00, 0.00, 1.00, 0.50],
    [0.00, 0.50, 1.00, 0.50],
  ],
  3: [
    [0.00, 0.00, 1.00, 0.56],
    [0.00, 0.56, 0.50, 0.44],
    [0.50, 0.56, 0.50, 0.44],
  ],
  4: [
    [0.00, 0.00, 0.50, 0.50],
    [0.50, 0.00, 0.50, 0.50],
    [0.00, 0.50, 0.50, 0.50],
    [0.50, 0.50, 0.50, 0.50],
  ],
  5: [
    [0.000, 0.00, 0.500, 0.44],
    [0.500, 0.00, 0.500, 0.44],
    [0.000, 0.44, 0.334, 0.56],
    [0.334, 0.44, 0.333, 0.56],
    [0.667, 0.44, 0.333, 0.56],
  ],
  6: [
    [0.00, 0.000, 0.50, 0.334],
    [0.50, 0.000, 0.50, 0.334],
    [0.00, 0.334, 0.50, 0.333],
    [0.50, 0.334, 0.50, 0.333],
    [0.00, 0.667, 0.50, 0.333],
    [0.50, 0.667, 0.50, 0.333],
  ],
  7: [
    [0.000, 0.000, 0.500, 0.334],
    [0.500, 0.000, 0.500, 0.334],
    [0.000, 0.334, 0.500, 0.333],
    [0.500, 0.334, 0.500, 0.333],
    [0.000, 0.667, 0.334, 0.333],
    [0.334, 0.667, 0.333, 0.333],
    [0.667, 0.667, 0.333, 0.333],
  ],
  8: [
    [0.000, 0.000, 0.334, 0.334],
    [0.334, 0.000, 0.333, 0.334],
    [0.667, 0.000, 0.333, 0.334],
    [0.000, 0.334, 0.334, 0.333],
    [0.334, 0.334, 0.333, 0.333],
    [0.667, 0.334, 0.333, 0.333],
    [0.000, 0.667, 0.500, 0.333],
    [0.500, 0.667, 0.500, 0.333],
  ],
  9: [
    [0.000, 0.000, 0.334, 0.334],
    [0.334, 0.000, 0.333, 0.334],
    [0.667, 0.000, 0.333, 0.334],
    [0.000, 0.334, 0.334, 0.333],
    [0.334, 0.334, 0.333, 0.333],
    [0.667, 0.334, 0.333, 0.333],
    [0.000, 0.667, 0.334, 0.333],
    [0.334, 0.667, 0.333, 0.333],
    [0.667, 0.667, 0.333, 0.333],
  ],
};

List<List<double>> _layoutFor(int count) {
  final c = count.clamp(1, 9);
  return _storiesLayouts[c] ?? _storiesLayouts[6]!;
}

/// 隙間なし（シームレス）。小数誤差による髪の毛1px隙間を防ぐため
/// 右・下エッジでない辺は 0.5px だけはみ出す。
Rect _slotToRect(List<double> s, double w, double h) {
  const eps = 0.001;
  const overshoot = 0.5;
  final isRight = s[0] + s[2] > 1 - eps;
  final isBottom = s[1] + s[3] > 1 - eps;
  return Rect.fromLTRB(
    s[0] * w,
    s[1] * h,
    (s[0] + s[2]) * w + (isRight ? 0 : overshoot),
    (s[1] + s[3]) * h + (isBottom ? 0 : overshoot),
  );
}

/// 画像パスのリストから、ストーリー風コラージュを表示して
/// カメラロールへ保存できる画面（対戦リザルトなどから使う）。
class StoriesCollageScreen extends StatefulWidget {
  final List<String> imagePaths;
  final String title;

  const StoriesCollageScreen({
    super.key,
    required this.imagePaths,
    this.title = 'コラージュ',
  });

  @override
  State<StoriesCollageScreen> createState() => _StoriesCollageScreenState();
}

class _StoriesCollageScreenState extends State<StoriesCollageScreen> {
  final GlobalKey _repaintKey = GlobalKey();
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;

      final permission = await Permission.photos.request();
      if (!permission.isGranted && !permission.isLimited) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('写真ライブラリへのアクセスを許可してください')),
          );
        }
        return;
      }
      final result = await ImageGallerySaver.saveImage(
        data.buffer.asUint8List(),
        quality: 100,
        name: 'collage_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (!mounted) return;
      final ok = result['isSuccess'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'カメラロールに保存しました' : '保存に失敗しました')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存に失敗: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_alt),
            tooltip: '保存',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: RepaintBoundary(
            key: _repaintKey,
            child: StoriesCollage(imagePaths: widget.imagePaths),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_alt),
            label: const Text('保存'),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ),
      ),
    );
  }
}

/// インスタのストーリー風（9:16）の自動配置コラージュ。
///
/// [imagePaths] の枚数（1〜9）に応じたレイアウトへ写真を自動で流し込む。
/// 10枚以上のときは先頭9枚を使う。編集操作は持たない（自動配置専用）。
class StoriesCollage extends StatelessWidget {
  final List<String> imagePaths;

  const StoriesCollage({super.key, required this.imagePaths});

  @override
  Widget build(BuildContext context) {
    final paths = imagePaths.take(9).toList();
    if (paths.isEmpty) {
      return const AspectRatio(
        aspectRatio: 9 / 16,
        child: ColoredBox(color: Colors.black),
      );
    }
    final slots = _layoutFor(paths.length);

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: LayoutBuilder(
        builder: (_, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return Stack(
            children: [
              const ColoredBox(color: Colors.black, child: SizedBox.expand()),
              for (int i = 0; i < paths.length && i < slots.length; i++)
                Builder(
                  builder: (_) {
                    final r = _slotToRect(slots[i], w, h);
                    return Positioned(
                      left: r.left,
                      top: r.top,
                      width: r.width,
                      height: r.height,
                      child: paths[i].isNotEmpty
                          ? Image.file(File(paths[i]), fit: BoxFit.cover)
                          : ColoredBox(color: Colors.grey.shade900),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
