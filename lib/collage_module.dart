import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'photo_pin.dart';

import'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path_provider/path_provider.dart';

// =====================================================
// 共通：背景色
// =====================================================

Color getCollageBackgroundColorByColorId(int colorId) {
  switch (colorId) {
    case 0:
      return const Color(0xFFD6D6D6);
    case 1:
      return const Color(0xFFCCCCCC);
    case 2:
      return const Color(0xFFE0E0E0);
    case 3:
      return const Color(0xFFF2E8D8);
    case 4:
    case 5:
      return const Color(0xFFFFCFCF);
    case 6:
      return const Color(0xFFFFD6E5);
    case 7:
    case 23:
      return const Color(0xFFFFD9B3);
    case 8:
    case 9:
      return const Color(0xFFFFED99);
    case 10:
    case 11:
      return const Color(0xFFDDF4B5);
    case 12:
    case 13:
      return const Color(0xFFCFE8CF);
    case 14:
      return const Color(0xFFC9F3F3);
    case 15:
      return const Color(0xFFCDEFFF);
    case 16:
    case 17:
      return const Color(0xFFD3E0FF);
    case 18:
      return const Color(0xFFE4D4FF);
    case 19:
      return const Color(0xFFFFD1FF);
    case 20:
    case 21:
      return const Color(0xFFE0C3A3);
    case 22:
      return const Color(0xFFEAD3B0);
    default:
      return const Color(0xFFF0DFC8);
  }
}

// =====================================================
// 写真選択関数
// =====================================================

Future<List<PhotoPin>?> showAppPhotoPicker({
  required BuildContext context,
  required List<PhotoPin> pins,
  bool multiSelect = true,
}) async {
  final selected = <PhotoPin>{};

  return showModalBottomSheet<List<PhotoPin>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.72,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  const Text(
                    'アプリ内の写真から選択',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: pins.isEmpty
                        ? const Center(
                            child: Text('選択できる写真がありません'),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(12),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 6,
                            ),
                            itemCount: pins.length,
                            itemBuilder: (context, index) {
                              final pin = pins[index];
                              final isSelected = selected.contains(pin);

                              return GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    if (multiSelect) {
                                      if (isSelected) {
                                        selected.remove(pin);
                                      } else {
                                        selected.add(pin);
                                      }
                                    } else {
                                      selected
                                        ..clear()
                                        ..add(pin);
                                    }
                                  });
                                },
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.file(
                                        File(pin.imagePath),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    if (isSelected)
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: Colors.blueAccent,
                                            width: 4,
                                          ),
                                        ),
                                      ),
                                    if (isSelected)
                                      const Align(
                                        alignment: Alignment.topRight,
                                        child: Padding(
                                          padding: EdgeInsets.all(6),
                                          child: CircleAvatar(
                                            radius: 13,
                                            backgroundColor: Colors.blueAccent,
                                            child: Icon(
                                              Icons.check,
                                              color: Colors.white,
                                              size: 17,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('キャンセル'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: selected.isEmpty
                                ? null
                                : () {
                                    Navigator.pop(
                                      context,
                                      selected.toList(),
                                    );
                                  },
                            child: Text(multiSelect ? '追加' : '選択'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

// =====================================================
// 共通：選択した画像の縦横サイズを取得
// =====================================================

Future<Size> getImagePixelSizeFromFile(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    return Size(
      image.width.toDouble(),
      image.height.toDouble(),
    );
  } catch (_) {
    return const Size(1, 1);
  }
}

// =====================================================
// 共通：Widgetを画像として写真フォルダに保存
// =====================================================

Future<void> saveWidgetToGallery({
  required BuildContext context,
  required GlobalKey repaintKey,
  required String fileNamePrefix,
}) async {
  try {
    final boundary =
        repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

    if (boundary == null) return;

    final ui.Image image = await boundary.toImage(pixelRatio: 2.5);

    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    if (byteData == null) return;

    final Uint8List pngBytes = byteData.buffer.asUint8List();

    await ImageGallerySaver.saveImage(
      pngBytes,
      quality: 100,
      name: '${fileNamePrefix}_${DateTime.now().millisecondsSinceEpoch}',
    );

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('コラージュを写真フォルダに保存しました'),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('保存に失敗しました: $e'),
      ),
    );
  }
}

// =====================================================
// 共通：テスト画像生成
// =====================================================

Future<List<String>> createTestImages() async {
  final dir = await getApplicationDocumentsDirectory();
  final testDir = Directory('${dir.path}/test_images');

  if (!await testDir.exists()) {
    await testDir.create(recursive: true);
  }

  final testColors = [
    img.ColorRgb8(0, 0, 0),
    img.ColorRgb8(255, 0, 0),
    img.ColorRgb8(0, 255, 0),
    img.ColorRgb8(0, 0, 255),
    img.ColorRgb8(255, 255, 0),
    img.ColorRgb8(255, 0, 255),
    img.ColorRgb8(0, 255, 255),
    img.ColorRgb8(255, 220, 177),
  ];

  final paths = <String>[];

  for (int i = 0; i < testColors.length; i++) {
    final image = img.Image(width: 300, height: 300);
    img.fill(image, color: testColors[i]);

    final file = File('${testDir.path}/test_$i.jpg');
    await file.writeAsBytes(img.encodeJpg(image));

    paths.add(file.path);
  }

  return paths;
}

// ##########################################################################
// コラージュ1：自動配置コラージュ
// ##########################################################################

class AutoCollageSlot {
  final double x;
  final double y;
  final double w;
  final double h;
  final double angle;

  const AutoCollageSlot({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.angle,
  });
}

List<AutoCollageSlot> createAutoSlots({
  required int imageCount,
  required double canvasWidth,
  required double canvasHeight,
}) {
  if (imageCount <= 0) return [];

  if (imageCount == 1) {
    return [
      const AutoCollageSlot(x: 150, y: 250, w: 600, h: 520, angle: -0.025),
    ];
  }

  if (imageCount == 2) {
    return [
      const AutoCollageSlot(x: 110, y: 210, w: 390, h: 500, angle: -0.055),
      const AutoCollageSlot(x: 410, y: 390, w: 390, h: 500, angle: 0.055),
    ];
  }

  if (imageCount == 3) {
    return [
      const AutoCollageSlot(x: 95, y: 130, w: 500, h: 380, angle: -0.045),
      const AutoCollageSlot(x: 540, y: 500, w: 280, h: 300, angle: 0.06),
      const AutoCollageSlot(x: 120, y: 680, w: 390, h: 300, angle: 0.035),
    ];
  }

  if (imageCount == 4) {
    return [
      const AutoCollageSlot(x: 70, y: 120, w: 410, h: 310, angle: -0.045),
      const AutoCollageSlot(x: 500, y: 160, w: 320, h: 360, angle: 0.045),
      const AutoCollageSlot(x: 100, y: 610, w: 330, h: 340, angle: 0.05),
      const AutoCollageSlot(x: 455, y: 590, w: 380, h: 300, angle: -0.04),
    ];
  }

  if (imageCount == 5) {
    return [
      const AutoCollageSlot(x: 250, y: 260, w: 400, h: 360, angle: -0.02),
      const AutoCollageSlot(x: 65, y: 95, w: 300, h: 240, angle: -0.06),
      const AutoCollageSlot(x: 565, y: 120, w: 270, h: 270, angle: 0.055),
      const AutoCollageSlot(x: 90, y: 700, w: 310, h: 260, angle: 0.04),
      const AutoCollageSlot(x: 520, y: 710, w: 300, h: 250, angle: -0.05),
    ];
  }

  if (imageCount == 6) {
    return [
      const AutoCollageSlot(x: 70, y: 90, w: 390, h: 300, angle: -0.045),
      const AutoCollageSlot(x: 470, y: 120, w: 350, h: 300, angle: 0.04),
      const AutoCollageSlot(x: 90, y: 450, w: 260, h: 270, angle: 0.055),
      const AutoCollageSlot(x: 380, y: 430, w: 330, h: 290, angle: -0.035),
      const AutoCollageSlot(x: 80, y: 780, w: 340, h: 240, angle: -0.03),
      const AutoCollageSlot(x: 475, y: 760, w: 330, h: 260, angle: 0.045),
    ];
  }

  if (imageCount == 7) {
    return [
      const AutoCollageSlot(x: 50, y: 55, w: 340, h: 250, angle: -0.065),
      const AutoCollageSlot(x: 430, y: 80, w: 360, h: 260, angle: 0.055),
      const AutoCollageSlot(x: 95, y: 360, w: 390, h: 280, angle: 0.045),
      const AutoCollageSlot(x: 510, y: 380, w: 300, h: 310, angle: -0.055),
      const AutoCollageSlot(x: 55, y: 730, w: 300, h: 250, angle: 0.04),
      const AutoCollageSlot(x: 365, y: 730, w: 270, h: 270, angle: -0.045),
      const AutoCollageSlot(x: 650, y: 705, w: 220, h: 300, angle: 0.065),
    ];
  }

  if (imageCount == 8) {
    return [
      const AutoCollageSlot(x: 285, y: 340, w: 330, h: 310, angle: -0.015),
      const AutoCollageSlot(x: 55, y: 70, w: 280, h: 230, angle: -0.06),
      const AutoCollageSlot(x: 360, y: 80, w: 260, h: 230, angle: 0.035),
      const AutoCollageSlot(x: 635, y: 95, w: 220, h: 270, angle: 0.06),
      const AutoCollageSlot(x: 60, y: 380, w: 230, h: 290, angle: 0.05),
      const AutoCollageSlot(x: 625, y: 450, w: 240, h: 280, angle: -0.045),
      const AutoCollageSlot(x: 95, y: 760, w: 300, h: 250, angle: -0.035),
      const AutoCollageSlot(x: 470, y: 765, w: 330, h: 245, angle: 0.04),
    ];
  }

  if (imageCount == 9) {
    return [
      const AutoCollageSlot(x: 55, y: 60, w: 250, h: 240, angle: -0.05),
      const AutoCollageSlot(x: 325, y: 85, w: 250, h: 240, angle: 0.035),
      const AutoCollageSlot(x: 595, y: 65, w: 250, h: 240, angle: 0.055),
      const AutoCollageSlot(x: 75, y: 375, w: 250, h: 240, angle: 0.04),
      const AutoCollageSlot(x: 325, y: 365, w: 270, h: 260, angle: -0.025),
      const AutoCollageSlot(x: 615, y: 390, w: 230, h: 250, angle: -0.045),
      const AutoCollageSlot(x: 60, y: 720, w: 260, h: 240, angle: -0.035),
      const AutoCollageSlot(x: 335, y: 740, w: 250, h: 235, angle: 0.05),
      const AutoCollageSlot(x: 610, y: 715, w: 250, h: 250, angle: 0.03),
    ];
  }

  final columns = imageCount <= 12 ? 4 : 5;
  final rows = (imageCount / columns).ceil();

  const margin = 45.0;
  const gap = 24.0;

  final usableWidth = canvasWidth - margin * 2 - gap * (columns - 1);
  final usableHeight = canvasHeight - margin * 2 - gap * (rows - 1);

  final cellWidth = usableWidth / columns;
  final cellHeight = usableHeight / rows;

  final slots = <AutoCollageSlot>[];

  for (int i = 0; i < imageCount; i++) {
    final row = i ~/ columns;
    final col = i % columns;

    final shiftX = [-10.0, 8.0, -6.0, 12.0, -8.0, 5.0][i % 6];
    final shiftY = [6.0, -8.0, 10.0, -5.0, 4.0, -4.0][i % 6];

    final angle = [-0.05, 0.035, -0.03, 0.05, -0.025, 0.03][i % 6];

    slots.add(
      AutoCollageSlot(
        x: margin + col * (cellWidth + gap) + shiftX,
        y: margin + row * (cellHeight + gap) + shiftY,
        w: cellWidth,
        h: cellHeight,
        angle: angle,
      ),
    );
  }

  return slots;
}

class ScrapbookCollage extends StatelessWidget {
  final List<String> imagePaths;
  final int colorId;

  const ScrapbookCollage({
    super.key,
    required this.imagePaths,
    this.colorId = 12,
  });

  @override
  Widget build(BuildContext context) {
    const canvasWidth = 900.0;
    const canvasHeight = 1100.0;

    final slots = createAutoSlots(
      imageCount: imagePaths.length,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
    );

    final count = min(imagePaths.length, slots.length);
    final backgroundColor = getCollageBackgroundColorByColorId(colorId);

    return Container(
      width: canvasWidth,
      height: canvasHeight,
      color: backgroundColor,
      child: Stack(
        children: [
          for (int i = 0; i < count; i++)
            Positioned(
              left: slots[i].x,
              top: slots[i].y,
              child: Transform.rotate(
                angle: slots[i].angle,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFCF7),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 10,
                        offset: const Offset(6, 6),
                      ),
                    ],
                  ),
                  child: Image.file(
                    File(imagePaths[i]),
                    width: slots[i].w,
                    height: slots[i].h,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AutoCollagePage extends StatelessWidget {
  final List<String> imagePaths;
  final String title;
  final int colorId;

  AutoCollagePage({
    super.key,
    required this.imagePaths,
    this.title = 'コラージュ1：自動配置',
    this.colorId = 12,
  });

  final GlobalKey captureKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              width: 320,
              child: FittedBox(
                fit: BoxFit.contain,
                child: RepaintBoundary(
                  key: captureKey,
                  child: ScrapbookCollage(
                    imagePaths: imagePaths,
                    colorId: colorId,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                saveWidgetToGallery(
                  context: context,
                  repaintKey: captureKey,
                  fileNamePrefix: 'auto_collage',
                );
              },
              icon: const Icon(Icons.save_alt),
              label: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

// ##########################################################################

// コラージュ2：自由配置＋トリミングあり

// ##########################################################################

// =====================================================
// 背景
// =====================================================

enum CollageBackgroundType {
  color,
  gradient,
  image,
}

class CollageBackground {
  final CollageBackgroundType type;
  final Color color;
  final List<Color> gradientColors;
  final String? assetPath;

  const CollageBackground.color(this.color)
      : type = CollageBackgroundType.color,
        gradientColors = const [],
        assetPath = null;

  const CollageBackground.gradient(this.gradientColors)
      : type = CollageBackgroundType.gradient,
        color = Colors.white,
        assetPath = null;

  const CollageBackground.image(this.assetPath)
      : type = CollageBackgroundType.image,
        color = Colors.white,
        gradientColors = const [];
}

// =====================================================
// コラージュアイテム
// =====================================================

enum CollageItemType {
  photo,
  text,
  sticker,
}

enum ItemShape {
  rectangle,
  roundedRectangle,
  circle,
}

enum CropHandle {
  left,
  right,
  top,
  bottom,
}

class CollageItem {
  final String id;
  final CollageItemType type;

  double x;
  double y;
  double width;
  double height;
  double angle;

  // 写真用
  String? imagePath;
  ItemShape photoShape;
  // -1.0で暗く、0.0で通常、1.0で明るくします。
  double photoBrightness;
  // 写真のどの範囲を使うかを0〜1の正規化座標で保持します。
  Rect cropRectNormalized;
  bool hasCrop;
  double cropAngle;
  double? imagePixelWidth;
  double? imagePixelHeight;

  // テキスト用
  String? text;
  Color textColor;
  double fontSize;
  String? fontFamily;
  FontWeight fontWeight;
  FontStyle fontStyle;
  double letterSpacing;

  // スタンプ用
  String? assetPath;
  String? fallbackEmoji;

  CollageItem({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.angle = 0.0,
    this.imagePath,
    this.photoShape = ItemShape.rectangle,
    this.photoBrightness = 0.0,
    this.cropRectNormalized = const Rect.fromLTWH(0, 0, 1, 1),
    this.hasCrop = false,
    this.cropAngle = 0.0,
    this.imagePixelWidth,
    this.imagePixelHeight,
    this.text,
    this.textColor = Colors.black,
    this.fontSize = 48,
    this.fontFamily,
    this.fontWeight = FontWeight.bold,
    this.fontStyle = FontStyle.normal,
    this.letterSpacing = 0.0,
    this.assetPath,
    this.fallbackEmoji,
  });
}


class FontPreset {
  final String label;
  final String? family;
  final FontWeight weight;
  final FontStyle style;
  final double letterSpacing;

  const FontPreset({
    required this.label,
    required this.family,
    this.weight = FontWeight.bold,
    this.style = FontStyle.normal,
    this.letterSpacing = 0.0,
  });
}


// List<AutoCollageSlot> createAutoSlots({
//   required int imageCount,
//   required double canvasWidth,
//   required double canvasHeight,
// }) {
//   if (imageCount <= 0) return [];

//   if (imageCount == 1) {
//     return [
//       const AutoCollageSlot(x: 150, y: 250, w: 600, h: 520, angle: -0.025),
//     ];
//   }

//   if (imageCount == 2) {
//     return [
//       const AutoCollageSlot(x: 110, y: 210, w: 390, h: 500, angle: -0.055),
//       const AutoCollageSlot(x: 410, y: 390, w: 390, h: 500, angle: 0.055),
//     ];
//   }

//   if (imageCount == 3) {
//     return [
//       const AutoCollageSlot(x: 95, y: 130, w: 500, h: 380, angle: -0.045),
//       const AutoCollageSlot(x: 540, y: 500, w: 280, h: 300, angle: 0.06),
//       const AutoCollageSlot(x: 120, y: 680, w: 390, h: 300, angle: 0.035),
//     ];
//   }

//   if (imageCount == 4) {
//     return [
//       const AutoCollageSlot(x: 70, y: 120, w: 410, h: 310, angle: -0.045),
//       const AutoCollageSlot(x: 500, y: 160, w: 320, h: 360, angle: 0.045),
//       const AutoCollageSlot(x: 100, y: 610, w: 330, h: 340, angle: 0.05),
//       const AutoCollageSlot(x: 455, y: 590, w: 380, h: 300, angle: -0.04),
//     ];
//   }

//   final columns = imageCount <= 8 ? 3 : 4;
//   final rows = (imageCount / columns).ceil();
//   const margin = 55.0;
//   const gap = 28.0;
//   final usableWidth = canvasWidth - margin * 2 - gap * (columns - 1);
//   final usableHeight = canvasHeight - margin * 2 - gap * (rows - 1);
//   final cellWidth = usableWidth / columns;
//   final cellHeight = usableHeight / rows;
//   final slots = <AutoCollageSlot>[];

//   for (int i = 0; i < imageCount; i++) {
//     final row = i ~/ columns;
//     final col = i % columns;
//     final shiftX = [-10.0, 8.0, -6.0, 12.0][i % 4];
//     final shiftY = [6.0, -8.0, 10.0, -5.0][i % 4];
//     final angle = [-0.05, 0.035, -0.03, 0.05][i % 4];

//     slots.add(
//       AutoCollageSlot(
//         x: margin + col * (cellWidth + gap) + shiftX,
//         y: margin + row * (cellHeight + gap) + shiftY,
//         w: cellWidth,
//         h: cellHeight,
//         angle: angle,
//       ),
//     );
//   }

//   return slots;
// }

class EditableCollagePage extends StatefulWidget {
  final List<String> imagePaths;
  final List<PhotoPin> availablePins;
  final int? initialColorId;

  /// 「完成させる」時に、合成画像（PNG バイト列）を受け取って
  /// 保存・確定処理を行うコールバック。null の場合は「完成」ボタンを出さない。
  final Future<void> Function(Uint8List pngBytes)? onFinish;

  /// 「保存」時に、合成画像をアプリ内の「完成したコラージュ」一覧へも
  /// 追記するためのコールバック。null の場合はカメラロール保存のみ。
  /// （カメラロール保存・通知はエディタ側で行うので、この中では不要）
  final Future<void> Function(Uint8List pngBytes)? onSaveToGallery;

  /// 「完成」ボタンを表示するか。フォトモードの自由配置では保存＝一覧追加
  /// なので「完成」を出さず、保存ボタン1つに統一する。
  final bool showFinishButton;

  const EditableCollagePage({
    super.key,
    required this.imagePaths,
    this.availablePins = const [],
    this.initialColorId,
    this.onFinish,
    this.onSaveToGallery,
    this.showFinishButton = true,
  });

  @override
  State<EditableCollagePage> createState() => _EditableCollagePageState();
}

class _EditableCollagePageState extends State<EditableCollagePage> {
  static const double canvasWidth = 900.0;
  static const double canvasHeight = 1100.0;
  static const double displayWidth = 320.0;
  static const double displayScale = displayWidth / canvasWidth;
  static const double displayHeight = canvasHeight * displayScale;
  static const double touchScale = canvasWidth / displayWidth;

  final GlobalKey captureKey = GlobalKey();

  final List<Color> backgroundColors = const [
    Color(0xFFFFD6E5),
    Color(0xFFFFCFCF),
    Color(0xFFFFD9B3),
    Color(0xFFFFED99),
    Color(0xFFDDF4B5),
    Color(0xFFCFE8CF),
    Color(0xFFC9F3F3),
    Color(0xFFCDEFFF),
    Color(0xFFD3E0FF),
    Color(0xFFE4D4FF),
    Color(0xFFFFD1FF),
    Color(0xFFE0C3A3),
    Color(0xFFF2E8D8),
    Color(0xFFFFFCF7),
  ];

  final List<List<Color>> gradientBackgrounds = const [
    [Color(0xFFFFD6E5), Color(0xFFFFED99)],
    [Color(0xFFCDEFFF), Color(0xFFE4D4FF)],
    [Color(0xFFDDF4B5), Color(0xFFC9F3F3)],
    [Color(0xFFFFD9B3), Color(0xFFFFCFCF)],
    [Color(0xFFFFFFFF), Color(0xFFD3E0FF)],
  ];

  // assets/backgrounds/ と assets/stickers/ に入っている画像を自動で読み込みます。
  // pubspec.yaml には以下のようにフォルダ登録しておいてください。
  // assets:
  //   - assets/backgrounds/
  //   - assets/stickers/
  List<String> backgroundAssets = [];

  List<Map<String, String>> stickerPresets = [];

  Future<void> loadAssetLists() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final allAssets = manifest.listAssets();

    final backgrounds = allAssets
        .where((path) => path.startsWith('assets/backgrounds/'))
        .where(isImageAsset)
        .toList()
      ..sort();

    final stickers = allAssets
        .where((path) => path.startsWith('assets/stickers/'))
        .where(isImageAsset)
        .map((path) => {
              'asset': path,
              'emoji': '🖼️',
            })
        .toList()
      ..sort((a, b) => a['asset']!.compareTo(b['asset']!));

    if (!mounted) return;

    setState(() {
      backgroundAssets = backgrounds;
      stickerPresets = stickers;
    });
  }

  bool isImageAsset(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
  }

  final List<Color> textColors = const [
    Colors.black,
    Colors.white,
    Colors.red,
    Colors.pink,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.blue,
    Colors.purple,
    Color(0xFF8D5A2B),
  ];

  // iOS標準フォントを中心に10種類用意しています。
  // 端末にないフォント名は自動的に近い標準フォントにフォールバックします。
  final List<FontPreset> fontOptions = const [
    FontPreset(label: '標準', family: null, weight: FontWeight.w800),
    FontPreset(label: 'ゴシック', family: 'Hiragino Sans', weight: FontWeight.w900),
    FontPreset(label: '丸ゴシック', family: 'Hiragino Maru Gothic ProN', weight: FontWeight.w800),
    FontPreset(label: '明朝', family: 'Hiragino Mincho ProN', weight: FontWeight.w700),
    FontPreset(label: 'Helvetica', family: 'Helvetica', weight: FontWeight.w900),
    FontPreset(label: 'Avenir', family: 'Avenir Next', weight: FontWeight.w800),
    FontPreset(label: 'Georgia', family: 'Georgia', weight: FontWeight.w700),
    FontPreset(label: 'Times', family: 'Times New Roman', weight: FontWeight.w700),
    FontPreset(label: '等幅', family: 'Courier', weight: FontWeight.w700, letterSpacing: 1.2),
    FontPreset(label: '手書き風', family: 'Chalkboard SE', weight: FontWeight.w700, style: FontStyle.italic),
  ];

  late List<CollageItem> items;
  int selectedIndex = -1;
  int editTabIndex = 0;
  bool isSaving = false;

  // 直接操作用の一時状態
  // GestureDetectorはアイテム本体ではなくキャンバス全体で受けます。
  // これにより、選択中アイテムが小さくてもキャンバス上のどこでも操作できます。
  Offset startCanvasFocalPoint = Offset.zero;
  double startX = 0;
  double startY = 0;
  double startWidth = 0;
  double startHeight = 0;
  double startAngle = 0;
  double startFontSize = 48;
  CollageItem? gestureTargetItem;
  bool isPointerOnCanvas = false;

  // CollageBackground background = const CollageBackground.color(Color(0xFFCFE8CF));
  late CollageBackground background;

  CollageItem? get selectedItem {
    if (selectedIndex < 0 || selectedIndex >= items.length) return null;
    return items[selectedIndex];
  }

  @override
  void initState() {
    super.initState();

    loadAssetLists();

    background = CollageBackground.color(
      getCollageBackgroundColorByColorId(widget.initialColorId ?? 12),
    );

    final slots = createAutoSlots(
      imageCount: widget.imagePaths.length,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
    );

    items = [];

    for (int i = 0; i < widget.imagePaths.length; i++) {
      final slot = slots[i];
      items.add(
        CollageItem(
          id: 'photo_${DateTime.now().microsecondsSinceEpoch}_$i',
          type: CollageItemType.photo,
          imagePath: widget.imagePaths[i],
          x: slot.x,
          y: slot.y,
          width: slot.w,
          height: slot.h,
          angle: slot.angle,
        ),
      );
    }

    if (items.isNotEmpty) {
      selectedIndex = 0;
      editTabIndex = tabIndexForItemType(items.first.type);
    }
  }

  int tabIndexForItemType(CollageItemType type) {
    switch (type) {
      case CollageItemType.photo:
        return 0;
      case CollageItemType.text:
        return 1;
      case CollageItemType.sticker:
        return 2;
    }
  }

  void selectItem(CollageItem item) {
    setState(() {
      items.remove(item);
      items.add(item);
      selectedIndex = items.length - 1;
      editTabIndex = tabIndexForItemType(item.type);
    });
  }

  void clearSelectionForManualTab(int index) {
    setState(() {
      editTabIndex = index;
      selectedIndex = -1;
      gestureTargetItem = null;
    });
  }

  void deleteSelectedItem() {
    if (selectedItem == null) return;

    setState(() {
      items.removeAt(selectedIndex);
      if (items.isEmpty) {
        selectedIndex = -1;
      } else if (selectedIndex >= items.length) {
        selectedIndex = items.length - 1;
      }
    });
  }

  // 移動・拡大縮小・回転はキャンバス全体の onScaleStart/onScaleUpdate で直接操作します。

  Offset displayPointToCanvasPoint(Offset displayPoint) {
    return Offset(displayPoint.dx * touchScale, displayPoint.dy * touchScale);
  }

  Size getItemFrameSize(CollageItem item) {
    // 写真は白フチ用のpaddingが左右上下に7pxずつ入っているため、その分も当たり判定に含めます。
    if (item.type == CollageItemType.photo) {
      return Size(item.width + 14, item.height + 14);
    }
    return Size(item.width, item.height);
  }

  bool isCanvasPointInsideItem(Offset canvasPoint, CollageItem item) {
    final size = getItemFrameSize(item);
    final center = Offset(item.x + size.width / 2, item.y + size.height / 2);
    final p = canvasPoint - center;

    final cosA = cos(-item.angle);
    final sinA = sin(-item.angle);

    // 回転しているアイテムでも当たり判定できるよう、点の方を逆回転させます。
    final localX = p.dx * cosA - p.dy * sinA + size.width / 2;
    final localY = p.dx * sinA + p.dy * cosA + size.height / 2;

    return localX >= 0 &&
        localX <= size.width &&
        localY >= 0 &&
        localY <= size.height;
  }

  CollageItem? hitTestItemOnCanvas(Offset canvasPoint) {
    // Stackでは後ろにある要素ほど上に描画されるため、後ろから調べます。
    for (final item in items.reversed) {
      if (isCanvasPointInsideItem(canvasPoint, item)) {
        return item;
      }
    }
    return null;
  }

  void startCanvasGesture(ScaleStartDetails details) {
    final canvasPoint = displayPointToCanvasPoint(details.localFocalPoint);
    final tappedItem = hitTestItemOnCanvas(canvasPoint);

    CollageItem? target;

    setState(() {
      // アイテム上から操作を始めた場合は、そのアイテムを選択して最前面にし、
      // 操作パネルも写真/文字/飾りの対応タブへ自動で切り替えます。
      if (tappedItem != null) {
        items.remove(tappedItem);
        items.add(tappedItem);
        selectedIndex = items.length - 1;
        editTabIndex = tabIndexForItemType(tappedItem.type);
        target = tappedItem;
      } else {
        // 何もない場所から始めた場合は、現在選択中のアイテムを操作対象にします。
        // これにより、小さいアイテムでもキャンバス内の広い場所で2本指操作できます。
        target = selectedItem;
      }
    });

    gestureTargetItem = target;
    startCanvasFocalPoint = canvasPoint;

    if (target == null) return;

    startX = target!.x;
    startY = target!.y;
    startWidth = target!.width;
    startHeight = target!.height;
    startAngle = target!.angle;
    startFontSize = target!.fontSize;
  }

  void updateCanvasGesture(ScaleUpdateDetails details) {
    final item = gestureTargetItem;
    if (item == null) return;

    final canvasPoint = displayPointToCanvasPoint(details.localFocalPoint);
    final dx = canvasPoint.dx - startCanvasFocalPoint.dx;
    final dy = canvasPoint.dy - startCanvasFocalPoint.dy;
    final newScale = details.scale.clamp(0.25, 4.0);

    setState(() {
      item.x = startX + dx;
      item.y = startY + dy;
      item.angle = startAngle + details.rotation;

      if (item.type == CollageItemType.text) {
        item.width = (startWidth * newScale).clamp(120.0, 1000.0);
        item.height = (startHeight * newScale).clamp(60.0, 700.0);
        item.fontSize = (startFontSize * newScale).clamp(16.0, 180.0);
      } else {
        item.width = (startWidth * newScale).clamp(60.0, 1200.0);
        item.height = (startHeight * newScale).clamp(60.0, 1200.0);
      }

      if (item.type == CollageItemType.photo &&
          item.photoShape == ItemShape.circle) {
        final size = min(item.width, item.height).toDouble();
        item.width = size;
        item.height = size;
      }
    });
  }

  void endCanvasGesture() {
    gestureTargetItem = null;
  }

  // Future<void> addPhotos() async {
  //   final picker = ImagePicker();
  //   final files = await picker.pickMultiImage(imageQuality: 85);
  //   if (files.isEmpty) return;

  //   setState(() {
  //     for (final file in files) {
  //       final offset = (items.length % 6) * 35.0;
  //       items.add(
  //         CollageItem(
  //           id: 'photo_${DateTime.now().microsecondsSinceEpoch}_${items.length}',
  //           type: CollageItemType.photo,
  //           imagePath: file.path,
  //           x: 220 + offset,
  //           y: 260 + offset,
  //           width: 360,
  //           height: 300,
  //           angle: ((items.length % 5) - 2) * 0.035,
  //         ),
  //       );
  //     }
  //     selectedIndex = items.length - 1;
  //     editTabIndex = 0;
  //   });
  // }
  Future<void> addPhotos() async {
    if (widget.availablePins.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('追加できる写真がありません')),
      );
      return;
    }

    final selectedPins = await showAppPhotoPicker(
      context: context,
      pins: widget.availablePins,
      multiSelect: true,
    );

    if (selectedPins == null || selectedPins.isEmpty) return;

    setState(() {
      for (final pin in selectedPins) {
        final offset = (items.length % 6) * 35.0;

        items.add(
          CollageItem(
            id: 'photo_${DateTime.now().microsecondsSinceEpoch}_${items.length}',
            type: CollageItemType.photo,
            imagePath: pin.imagePath,
            x: 220 + offset,
            y: 260 + offset,
            width: 360,
            height: 300,
            angle: ((items.length % 5) - 2) * 0.035,
          ),
        );
      }

      selectedIndex = items.length - 1;
      editTabIndex = 0;
    });
  }

  Future<void> addTextItem() async {
    final controller = TextEditingController(text: 'TEXT');

    final text = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('テキストを追加'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '文字を入力',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('追加'),
            ),
          ],
        );
      },
    );

    if (text == null || text.trim().isEmpty) return;

    setState(() {
      items.add(
        CollageItem(
          id: 'text_${DateTime.now().microsecondsSinceEpoch}',
          type: CollageItemType.text,
          text: text.trim(),
          x: 190,
          y: 460,
          width: 520,
          height: 150,
          angle: -0.03,
          textColor: Colors.pink,
          fontSize: 64,
          fontFamily: 'Hiragino Maru Gothic ProN',
          fontWeight: FontWeight.w900,
        ),
      );
      selectedIndex = items.length - 1;
      editTabIndex = 1;
    });
  }

  Future<void> editSelectedText() async {
    final item = selectedItem;
    if (item == null || item.type != CollageItemType.text) return;

    final controller = TextEditingController(text: item.text ?? '');

    final text = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('テキストを編集'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '文字を入力'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('反映'),
            ),
          ],
        );
      },
    );

    if (text == null || text.trim().isEmpty) return;

    setState(() {
      item.text = text.trim();
    });
  }

  void addSticker(String assetPath, String fallbackEmoji) {
    setState(() {
      final offset = (items.length % 5) * 28.0;
      items.add(
        CollageItem(
          id: 'sticker_${DateTime.now().microsecondsSinceEpoch}',
          type: CollageItemType.sticker,
          assetPath: assetPath,
          fallbackEmoji: fallbackEmoji,
          x: 330 + offset,
          y: 360 + offset,
          width: 190,
          height: 190,
          angle: ((items.length % 5) - 2) * 0.06,
        ),
      );
      selectedIndex = items.length - 1;
      editTabIndex = 2;
    });
  }

  void changeSelectedTextColor(Color color) {
    final item = selectedItem;
    if (item == null || item.type != CollageItemType.text) return;

    setState(() {
      item.textColor = color;
    });
  }

  void changeSelectedFont(FontPreset preset) {
    final item = selectedItem;
    if (item == null || item.type != CollageItemType.text) return;

    setState(() {
      item.fontFamily = preset.family;
      item.fontWeight = preset.weight;
      item.fontStyle = preset.style;
      item.letterSpacing = preset.letterSpacing;
    });
  }

  void changeSelectedPhotoShape(ItemShape shape) {
    final item = selectedItem;
    if (item == null || item.type != CollageItemType.photo) return;

    setState(() {
      item.photoShape = shape;
      if (shape == ItemShape.circle) {
        final size = min(item.width, item.height).toDouble();
        item.width = size;
        item.height = size;
      }
    });
  }


  Rect keepNormalizedRectInside(Rect rect) {
    final left = rect.left.clamp(0.0, 1.0);
    final top = rect.top.clamp(0.0, 1.0);
    final width = rect.width.clamp(0.08, 1.0);
    final height = rect.height.clamp(0.08, 1.0);

    final fixedLeft = left.clamp(0.0, 1.0 - width);
    final fixedTop = top.clamp(0.0, 1.0 - height);

    return Rect.fromLTWH(fixedLeft, fixedTop, width, height);
  }

  Rect calculateCoverCropNormalized({
    required double imageWidth,
    required double imageHeight,
    required double frameWidth,
    required double frameHeight,
  }) {
    if (imageWidth <= 0 || imageHeight <= 0 || frameWidth <= 0 || frameHeight <= 0) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }

    final imageAspect = imageWidth / imageHeight;
    final frameAspect = frameWidth / frameHeight;

    if (imageAspect > frameAspect) {
      final visibleWidth = (frameAspect / imageAspect).clamp(0.08, 1.0);
      return Rect.fromLTWH((1.0 - visibleWidth) / 2.0, 0, visibleWidth, 1);
    } else {
      final visibleHeight = (imageAspect / frameAspect).clamp(0.08, 1.0);
      return Rect.fromLTWH(0, (1.0 - visibleHeight) / 2.0, 1, visibleHeight);
    }
  }

  Rect makeVisualSquareCropRect({
    required Offset center,
    required double previewWidth,
    required double previewHeight,
    double? currentVisualWidth,
    double? currentVisualHeight,
  }) {
    if (previewWidth <= 0 || previewHeight <= 0) {
      return keepNormalizedRectInside(
        Rect.fromCenter(center: center, width: 0.7, height: 0.7),
      );
    }

    final maxVisualSize = min(previewWidth, previewHeight);
    final visualSize = currentVisualWidth != null && currentVisualHeight != null
        ? min(currentVisualWidth, currentVisualHeight)
        : maxVisualSize * 0.68;
    final safeVisualSize = visualSize.clamp(32.0, maxVisualSize).toDouble();

    return keepNormalizedRectInside(
      Rect.fromCenter(
        center: center,
        width: safeVisualSize / previewWidth,
        height: safeVisualSize / previewHeight,
      ),
    );
  }

  Future<Size> getImagePixelSize(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      return Size(image.width.toDouble(), image.height.toDouble());
    } catch (_) {
      return const Size(1, 1);
    }
  }

  void moveEditingCropRect({
    required Rect current,
    required double dx,
    required double dy,
    required void Function(Rect) update,
  }) {
    update(keepNormalizedRectInside(current.translate(dx, dy)));
  }

  void resizeEditingCropRect({
    required Rect current,
    required double amount,
    required void Function(Rect) update,
  }) {
    final center = current.center;
    final newWidth = (current.width + amount).clamp(0.08, 1.0);
    final newHeight = (current.height + amount).clamp(0.08, 1.0);
    update(
      keepNormalizedRectInside(
        Rect.fromCenter(center: center, width: newWidth, height: newHeight),
      ),
    );
  }

  void stretchEditingCropRect({
    required Rect current,
    required double dw,
    required double dh,
    required void Function(Rect) update,
  }) {
    final center = current.center;
    final newWidth = (current.width + dw).clamp(0.08, 1.0);
    final newHeight = (current.height + dh).clamp(0.08, 1.0);
    update(
      keepNormalizedRectInside(
        Rect.fromCenter(center: center, width: newWidth, height: newHeight),
      ),
    );
  }

  Future<void> openDetailedCropOverlay() async {
    final item = selectedItem;
    if (item == null || item.type != CollageItemType.photo || item.imagePath == null) {
      showNeedPhotoSnackBar();
      return;
    }

    final imageSize = await getImagePixelSize(item.imagePath!);
    item.imagePixelWidth = imageSize.width;
    item.imagePixelHeight = imageSize.height;

    Rect editingCropRect = item.hasCrop
        ? keepNormalizedRectInside(item.cropRectNormalized)
        : const Rect.fromLTWH(0.15, 0.15, 0.7, 0.7);
    ItemShape editingShape = item.photoShape;
    double editingCropAngle = item.cropAngle;

    Offset cropStartFocalPoint = Offset.zero;
    Offset cropStartLocalFocalPoint = Offset.zero;
    Rect cropStartRect = editingCropRect;
    double cropStartAngle = editingCropAngle;
    Rect handleStartRect = editingCropRect;
    CropHandle? activeCropHandle;
    double lastCropPreviewWidth = 1.0;
    double lastCropPreviewHeight = 1.0;
    var didInitializeCropRectForPreview = item.hasCrop;

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void applyCrop() {
              setState(() {
                final crop = keepNormalizedRectInside(editingCropRect);
                item.cropRectNormalized = crop;
                item.hasCrop = true;
                item.photoShape = editingShape;
                item.cropAngle = editingCropAngle;
                item.imagePixelWidth = imageSize.width;
                item.imagePixelHeight = imageSize.height;

                // トリミング後は、写真アイテム自体の縦横比も
                // 選んだ切り抜き枠の見た目に合わせます。
                // これをしないと、元の写真フレームの比率が残り、
                // 切り抜き外の余白が白く見えてしまいます。
                final visualCropWidth = (crop.width * lastCropPreviewWidth).clamp(1.0, double.infinity).toDouble();
                final visualCropHeight = (crop.height * lastCropPreviewHeight).clamp(1.0, double.infinity).toDouble();

                // 回転したトリミング枠は、見た目上の外接矩形が
                // 実際にキャンバスへ置かれる写真アイテムのサイズになります。
                // ここを未回転の crop.width / crop.height だけで決めると、
                // 反映後に斜めトリミングが別物に見えます。
                final cosA = cos(editingCropAngle).abs();
                final sinA = sin(editingCropAngle).abs();
                final visualBoundingWidth = visualCropWidth * cosA + visualCropHeight * sinA;
                final visualBoundingHeight = visualCropWidth * sinA + visualCropHeight * cosA;
                final cropAspect = visualBoundingWidth / visualBoundingHeight;

                final currentArea = (item.width * item.height).clamp(3600.0, double.infinity).toDouble();
                final newWidth = sqrt(currentArea * cropAspect).clamp(70.0, 1200.0).toDouble();
                final newHeight = (newWidth / cropAspect).clamp(70.0, 1200.0).toDouble();
                item.width = newWidth;
                item.height = newHeight;
              });
              Navigator.pop(dialogContext);
            }

            void resetCrop() {
              setModalState(() {
                editingCropRect = makeVisualSquareCropRect(
                  center: const Offset(0.5, 0.5),
                  previewWidth: lastCropPreviewWidth,
                  previewHeight: lastCropPreviewHeight,
                );
                editingCropAngle = 0.0;
                editingShape = ItemShape.rectangle;
              });
            }

            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('写真をトリミング'),
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                  actions: [
                    TextButton(
                      onPressed: applyCrop,
                      child: const Text('反映'),
                    ),
                  ],
                ),
                body: SafeArea(
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          '枠内を1本指で移動、2本指で拡大・縮小・枠回転できます。白いハンドルをドラッグすると横だけ・縦だけ伸ばせます。丸も楕円にできます。',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final imageAspect = imageSize.width / imageSize.height;
                            var previewWidth = constraints.maxWidth - 44;
                            var previewHeight = previewWidth / imageAspect;

                            if (previewHeight > constraints.maxHeight) {
                              previewHeight = constraints.maxHeight;
                              previewWidth = previewHeight * imageAspect;
                            }

                            // 下部の形状切り替えボタンでも、現在のプレビュー実寸を使って
                            // 「丸」が画面上で正円になるようにします。
                            lastCropPreviewWidth = previewWidth;
                            lastCropPreviewHeight = previewHeight;

                            if (!didInitializeCropRectForPreview) {
                              didInitializeCropRectForPreview = true;
                              editingCropRect = makeVisualSquareCropRect(
                                center: const Offset(0.5, 0.5),
                                previewWidth: previewWidth,
                                previewHeight: previewHeight,
                              );
                            }

                            final cropRectPx = Rect.fromLTWH(
                              editingCropRect.left * previewWidth,
                              editingCropRect.top * previewHeight,
                              editingCropRect.width * previewWidth,
                              editingCropRect.height * previewHeight,
                            );
                            final visibleCropAngle = editingCropAngle;

                            Offset rotatePoint(Offset point, Offset center, double angle) {
                              final dx = point.dx - center.dx;
                              final dy = point.dy - center.dy;
                              final c = cos(angle);
                              final sn = sin(angle);
                              return Offset(
                                center.dx + dx * c - dy * sn,
                                center.dy + dx * sn + dy * c,
                              );
                            }

                            Offset rotateVector(Offset vector, double angle) {
                              final c = cos(angle);
                              final sn = sin(angle);
                              return Offset(
                                vector.dx * c - vector.dy * sn,
                                vector.dx * sn + vector.dy * c,
                              );
                            }

                            Offset unrotateVector(Offset vector, double angle) {
                              return rotateVector(vector, -angle);
                            }

                            final cropCenterPx = cropRectPx.center;
                            final handleCenters = <CropHandle, Offset>{
                              CropHandle.left: rotatePoint(cropRectPx.centerLeft, cropCenterPx, visibleCropAngle),
                              CropHandle.right: rotatePoint(cropRectPx.centerRight, cropCenterPx, visibleCropAngle),
                              CropHandle.top: rotatePoint(cropRectPx.topCenter, cropCenterPx, visibleCropAngle),
                              CropHandle.bottom: rotatePoint(cropRectPx.bottomCenter, cropCenterPx, visibleCropAngle),
                            };

                            Rect circleRectFromVisualSize({
                              required Offset centerNorm,
                              required double sizePx,
                            }) {
                              final safeSizePx = sizePx.clamp(32.0, min(previewWidth, previewHeight)).toDouble();
                              final rect = Rect.fromCenter(
                                center: centerNorm,
                                width: safeSizePx / previewWidth,
                                height: safeSizePx / previewHeight,
                              );
                              return keepNormalizedRectInside(rect);
                            }

                            Rect forceVisualCircleRect(Rect rect) {
                              final sizePx = min(rect.width * previewWidth, rect.height * previewHeight);
                              return circleRectFromVisualSize(
                                centerNorm: rect.center,
                                sizePx: sizePx,
                              );
                            }

                            CropHandle? hitTestCropHandle(Offset point) {
                              const threshold = 42.0;
                              CropHandle? nearest;
                              double nearestDistance = double.infinity;

                              for (final entry in handleCenters.entries) {
                                final distance = (point - entry.value).distance;
                                if (distance < threshold && distance < nearestDistance) {
                                  nearest = entry.key;
                                  nearestDistance = distance;
                                }
                              }

                              return nearest;
                            }

                            Rect stretchCropFromNormalizedDelta(
                              CropHandle handle,
                              Offset delta,
                            ) {
                              final localDelta = unrotateVector(delta, visibleCropAngle);
                              var width = handleStartRect.width;
                              var height = handleStartRect.height;
                              var centerShiftLocal = Offset.zero;

                              switch (handle) {
                                case CropHandle.left:
                                  width = (handleStartRect.width - localDelta.dx).clamp(0.08, 1.0).toDouble();
                                  centerShiftLocal = Offset(localDelta.dx / 2, 0);
                                  break;
                                case CropHandle.right:
                                  width = (handleStartRect.width + localDelta.dx).clamp(0.08, 1.0).toDouble();
                                  centerShiftLocal = Offset(localDelta.dx / 2, 0);
                                  break;
                                case CropHandle.top:
                                  height = (handleStartRect.height - localDelta.dy).clamp(0.08, 1.0).toDouble();
                                  centerShiftLocal = Offset(0, localDelta.dy / 2);
                                  break;
                                case CropHandle.bottom:
                                  height = (handleStartRect.height + localDelta.dy).clamp(0.08, 1.0).toDouble();
                                  centerShiftLocal = Offset(0, localDelta.dy / 2);
                                  break;
                              }

                              final centerShift = rotateVector(centerShiftLocal, visibleCropAngle);
                              final nextCenter = handleStartRect.center + centerShift;

                              return keepNormalizedRectInside(
                                Rect.fromCenter(
                                  center: nextCenter,
                                  width: width,
                                  height: height,
                                ),
                              );
                            }

                            return Center(
                              child: SizedBox(
                                width: previewWidth,
                                height: previewHeight,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Container(color: Colors.black),
                                      Image.file(
                                        File(item.imagePath!),
                                        fit: BoxFit.contain,
                                      ),
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onScaleStart: (details) {
                                          cropStartFocalPoint = details.focalPoint;
                                          cropStartLocalFocalPoint = details.localFocalPoint;
                                          cropStartRect = editingCropRect;
                                          cropStartAngle = editingCropAngle;
                                          handleStartRect = editingCropRect;
                                          activeCropHandle = details.pointerCount == 1
                                              ? hitTestCropHandle(details.localFocalPoint)
                                              : null;
                                        },
                                        onScaleUpdate: (details) {
                                          // 1本指でハンドル付近から始めた場合は、横だけ/縦だけ伸縮します。
                                          if (activeCropHandle != null && details.pointerCount == 1) {
                                            final delta = Offset(
                                              (details.localFocalPoint.dx - cropStartLocalFocalPoint.dx) / previewWidth,
                                              (details.localFocalPoint.dy - cropStartLocalFocalPoint.dy) / previewHeight,
                                            );
                                            setModalState(() {
                                              editingCropRect = stretchCropFromNormalizedDelta(
                                                activeCropHandle!,
                                                delta,
                                              );
                                            });
                                            return;
                                          }

                                          final dx = (details.focalPoint.dx - cropStartFocalPoint.dx) / previewWidth;
                                          final dy = (details.focalPoint.dy - cropStartFocalPoint.dy) / previewHeight;

                                          final newWidth = (cropStartRect.width * details.scale).clamp(0.08, 1.0).toDouble();
                                          final newHeight = (cropStartRect.height * details.scale).clamp(0.08, 1.0).toDouble();

                                          final newCenter = cropStartRect.center + Offset(dx, dy);
                                          final nextRect = Rect.fromCenter(
                                            center: newCenter,
                                            width: newWidth,
                                            height: newHeight,
                                          );

                                          setModalState(() {
                                            editingCropRect = keepNormalizedRectInside(nextRect);
                                            if (details.pointerCount >= 2) {
                                              // 回転するのは画像ではなく、トリミング枠です。
                                              editingCropAngle = cropStartAngle + details.rotation;
                                            }
                                          });
                                        },
                                        onScaleEnd: (_) {
                                          activeCropHandle = null;
                                        },
                                      ),
                                      IgnorePointer(
                                        child: CustomPaint(
                                          painter: DetailedCropOverlayPainter(
                                            cropRectNormalized: editingCropRect,
                                            cropShape: editingShape,
                                            cropAngle: visibleCropAngle,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFFCF7),
                          border: Border(top: BorderSide(color: Colors.black12)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                ChoiceChip(
                                  label: const Text('四角'),
                                  selected: editingShape == ItemShape.rectangle,
                                  onSelected: (_) => setModalState(() {
                                    editingShape = ItemShape.rectangle;
                                    editingCropRect = makeVisualSquareCropRect(
                                      center: editingCropRect.center,
                                      previewWidth: lastCropPreviewWidth,
                                      previewHeight: lastCropPreviewHeight,
                                      currentVisualWidth: editingCropRect.width * lastCropPreviewWidth,
                                      currentVisualHeight: editingCropRect.height * lastCropPreviewHeight,
                                    );
                                  }),
                                ),
                                ChoiceChip(
                                  label: const Text('角丸'),
                                  selected: editingShape == ItemShape.roundedRectangle,
                                  onSelected: (_) => setModalState(() => editingShape = ItemShape.roundedRectangle),
                                ),
                                ChoiceChip(
                                  label: const Text('丸'),
                                  selected: editingShape == ItemShape.circle,
                                  onSelected: (_) => setModalState(() {
                                    editingShape = ItemShape.circle;
                                    final center = editingCropRect.center;
                                    final visualSizePx = min(
                                      editingCropRect.width * lastCropPreviewWidth,
                                      editingCropRect.height * lastCropPreviewHeight,
                                    ).clamp(32.0, min(lastCropPreviewWidth, lastCropPreviewHeight)).toDouble();
                                    editingCropRect = keepNormalizedRectInside(
                                      Rect.fromCenter(
                                        center: center,
                                        width: visualSizePx / lastCropPreviewWidth,
                                        height: visualSizePx / lastCropPreviewHeight,
                                      ),
                                    );
                                  }),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton(
                                  onPressed: resetCrop,
                                  child: const Text('リセット'),
                                ),
                                FilledButton.icon(
                                  onPressed: applyCrop,
                                  icon: const Icon(Icons.check),
                                  label: const Text('反映'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> saveCollageWithoutSelection() async {
    if (isSaving) return;

    final oldSelectedIndex = selectedIndex;

    setState(() {
      isSaving = true;
      selectedIndex = -1;
    });

    // 選択枠が消えた状態で再描画されるのを待つ
    await Future.delayed(const Duration(milliseconds: 80));

    if (!mounted) return;

    try {
      final boundary =
          captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();

      // 1) カメラロールへ保存
      await ImageGallerySaver.saveImage(
        bytes,
        quality: 100,
        name: 'prikura_collage_${DateTime.now().millisecondsSinceEpoch}',
      );

      // 2) コールバックがあれば、アプリ内「完成したコラージュ」一覧へも追記
      final onSaveToGallery = widget.onSaveToGallery;
      if (onSaveToGallery != null) {
        await onSaveToGallery(bytes);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              onSaveToGallery != null
                  ? 'コラージュ一覧とカメラロールに保存しました'
                  : 'コラージュを写真フォルダに保存しました',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          selectedIndex = oldSelectedIndex;
          isSaving = false;
        });
      }
    }
  }

  Widget buildBackground() {
    switch (background.type) {
      case CollageBackgroundType.color:
        return Container(color: background.color);

      case CollageBackgroundType.gradient:
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: background.gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        );

      case CollageBackgroundType.image:
        return Image.asset(
          background.assetPath ?? '',
          width: canvasWidth,
          height: canvasHeight,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFFFCF7), Color(0xFFFFD6E5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: CustomPaint(
                painter: DottedBackgroundPainter(),
              ),
            );
          },
        );
    }
  }

  Widget buildCollageItem(CollageItem item, int index) {
    final isSelected = selectedIndex == index;

    return Positioned(
      left: item.x,
      top: item.y,
      child: Transform.rotate(
        angle: item.angle,
        child: buildItemFrame(
          item: item,
          isSelected: isSelected,
        ),
      ),
    );
  }

  Widget buildItemFrame({
    required CollageItem item,
    required bool isSelected,
  }) {
    final border = Border.all(
      color: isSelected ? Colors.blueAccent : Colors.transparent,
      width: isSelected ? 5 : 0,
    );

    switch (item.type) {
      case CollageItemType.photo:
        return buildPhotoFrame(
          item: item,
          isSelected: isSelected,
        );

      case CollageItemType.text:
        return Container(
          width: item.width,
          height: item.height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: border,
            borderRadius: BorderRadius.circular(12),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              item.text ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: item.textColor,
                fontSize: item.fontSize,
                fontFamily: item.fontFamily,
                fontWeight: item.fontWeight,
                fontStyle: item.fontStyle,
                letterSpacing: item.letterSpacing,
                shadows: const [
                  Shadow(
                    color: Colors.white,
                    blurRadius: 4,
                    offset: Offset(2, 2),
                  ),
                  Shadow(
                    color: Colors.white,
                    blurRadius: 4,
                    offset: Offset(-2, -2),
                  ),
                ],
              ),
            ),
          ),
        );

      case CollageItemType.sticker:
        return Container(
          width: item.width,
          height: item.height,
          decoration: BoxDecoration(
            border: border,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Image.asset(
            item.assetPath ?? '',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) {
              return Center(
                child: Text(
                  item.fallbackEmoji ?? '✨',
                  style: TextStyle(fontSize: item.width * 0.55),
                ),
              );
            },
          ),
        );
    }
  }

  Widget buildPhotoFrame({
    required CollageItem item,
    required bool isSelected,
  }) {
    // 写真の外側に白いContainerを敷くと、トリミング後に
    // 「切り抜き範囲外の白い余白」が見えてしまうため、
    // 写真本体は透明背景のまま、選択中だけ形に沿った枠線を描きます。
    return SizedBox(
      width: item.width,
      height: item.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: buildShapedPhoto(item),
          ),
          if (isSelected)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: PhotoSelectionBorderPainter(
                    shape: item.photoShape,
                    angle: item.cropAngle,
                    color: Colors.blueAccent,
                    strokeWidth: 4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget buildShapedPhoto(CollageItem item) {
    if (item.hasCrop &&
        item.imagePixelWidth != null &&
        item.imagePixelHeight != null) {
      return buildCroppedPhotoWithRotatedFrame(item);
    }

    final content = buildPhotoImageContent(item);

    return ClipPath(
      clipper: PhotoShapeClipper(
        shape: item.photoShape,
        angle: 0.0,
      ),
      child: SizedBox(
        width: item.width,
        height: item.height,
        child: content,
      ),
    );
  }

  Widget buildPhotoImageContent(CollageItem item) {
    final imagePath = item.imagePath;
    if (imagePath == null || imagePath.isEmpty) {
      return Container(color: Colors.grey.shade200);
    }

    return ColorFiltered(
      colorFilter: ColorFilter.matrix(
        brightnessMatrix(item.photoBrightness),
      ),
      child: Image.file(
        File(imagePath),
        fit: BoxFit.cover,
      ),
    );
  }

  Widget buildCroppedPhotoWithRotatedFrame(CollageItem item) {
    final imagePath = item.imagePath;
    if (imagePath == null || imagePath.isEmpty) {
      return const SizedBox.shrink();
    }

    final crop = keepNormalizedRectInside(item.cropRectNormalized);
    final imageWidth = item.imagePixelWidth!.clamp(1.0, double.infinity).toDouble();
    final imageHeight = item.imagePixelHeight!.clamp(1.0, double.infinity).toDouble();

    final cropPixelWidth = (crop.width * imageWidth).clamp(1.0, double.infinity).toDouble();
    final cropPixelHeight = (crop.height * imageHeight).clamp(1.0, double.infinity).toDouble();

    // トリミング枠を回転させたときの外接矩形を、写真アイテム全体の表示領域とみなします。
    // これにより、トリミング画面で見た「斜めの四角/角丸/丸」が反映後も同じ見た目になります。
    final cosA = cos(item.cropAngle).abs();
    final sinA = sin(item.cropAngle).abs();
    final rotatedBoundingWidth = cropPixelWidth * cosA + cropPixelHeight * sinA;
    final rotatedBoundingHeight = cropPixelWidth * sinA + cropPixelHeight * cosA;

    final scale = min(
      item.width / rotatedBoundingWidth,
      item.height / rotatedBoundingHeight,
    );

    final cropFrameWidth = cropPixelWidth * scale;
    final cropFrameHeight = cropPixelHeight * scale;
    final cropFrameRect = Rect.fromCenter(
      center: Offset(item.width / 2, item.height / 2),
      width: cropFrameWidth,
      height: cropFrameHeight,
    );

    final fullDisplayWidth = imageWidth * scale;
    final fullDisplayHeight = imageHeight * scale;

    // 元画像上の crop 中心が、写真アイテム中心に来るように配置します。
    // crop.left/top だけを基準にすると、回転時に選んだ範囲と反映後がズレます。
    final cropCenterXInImage = crop.center.dx * imageWidth;
    final cropCenterYInImage = crop.center.dy * imageHeight;
    final imageLeft = item.width / 2 - cropCenterXInImage * scale;
    final imageTop = item.height / 2 - cropCenterYInImage * scale;

    return ClipPath(
      clipper: RotatedCropFrameClipper(
        shape: item.photoShape,
        cropFrameRect: cropFrameRect,
        angle: item.cropAngle,
      ),
      child: SizedBox(
        width: item.width,
        height: item.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: imageLeft,
              top: imageTop,
              width: fullDisplayWidth,
              height: fullDisplayHeight,
              child: ColorFiltered(
                colorFilter: ColorFilter.matrix(
                  brightnessMatrix(item.photoBrightness),
                ),
                child: Image.file(
                  File(imagePath),
                  width: fullDisplayWidth,
                  height: fullDisplayHeight,
                  fit: BoxFit.fill,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<double> brightnessMatrix(double brightness) {
    final value = brightness.clamp(-1.0, 1.0) * 255.0;
    return <double>[
      1, 0, 0, 0, value,
      0, 1, 0, 0, value,
      0, 0, 1, 0, value,
      0, 0, 0, 1, 0,
    ];
  }

  Widget buildHeaderTip() {
    final item = selectedItem;
    String label = '素材をタップして選択 / 1本指で移動 / 2本指で拡大・回転';

    if (item != null) {
      switch (item.type) {
        case CollageItemType.photo:
          label = '選択中：写真　1本指で移動、2本指で拡大・回転';
          break;
        case CollageItemType.text:
          label = '選択中：テキスト　下のパネルで文字・色・書体を編集';
          break;
        case CollageItemType.sticker:
          label = '選択中：スタンプ　1本指で移動、2本指で拡大・回転';
          break;
      }
    }

    return Container(
      width: displayWidth,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }

  Widget buildSelectedActions() {
    final item = selectedItem;
    if (item == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text(
          '素材をタップすると、ここに編集メニューが出ます。',
          style: TextStyle(fontSize: 12, color: Colors.black54),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: deleteSelectedItem,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('削除'),
        ),
        if (item.type == CollageItemType.photo)
          OutlinedButton.icon(
            onPressed: openDetailedCropOverlay,
            icon: const Icon(Icons.crop, size: 18),
            label: const Text('トリミング'),
          ),
        if (item.type == CollageItemType.photo)
          OutlinedButton.icon(
            onPressed: showPhotoBrightnessSheet,
            icon: const Icon(Icons.brightness_6_outlined, size: 18),
            label: const Text('明るさ'),
          ),
      ],
    );
  }

  Widget buildCommonTools() {
    return const Padding(
      padding: EdgeInsets.only(top: 8),
      child: Text(
        '移動・拡大縮小・回転はキャンバス上で直接操作できます。',
        style: TextStyle(fontSize: 12, color: Colors.black54),
        textAlign: TextAlign.center,
      ),
    );
  }

  void showNeedPhotoSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('先に写真を選択してください')),
    );
  }

  Future<void> showPhotoBrightnessSheet() async {
    final item = selectedItem;
    if (item == null || item.type != CollageItemType.photo) {
      showNeedPhotoSnackBar();
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '写真の明るさ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.photoBrightness == 0
                          ? '標準'
                          : item.photoBrightness > 0
                              ? '明るめ'
                              : '暗め',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    Slider(
                      value: item.photoBrightness,
                      min: -0.6,
                      max: 0.6,
                      divisions: 24,
                      label: item.photoBrightness.toStringAsFixed(2),
                      onChanged: (value) {
                        setState(() {
                          item.photoBrightness = value;
                        });
                        setModalState(() {});
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              item.photoBrightness = 0.0;
                            });
                            setModalState(() {});
                          },
                          child: const Text('リセット'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('完了'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget buildPhotoTools() {
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: addPhotos,
          icon: const Icon(Icons.add_photo_alternate),
          label: const Text('写真を追加'),
        ),
        const SizedBox(height: 10),
        buildSelectedActions(),
        const SizedBox(height: 6),
        buildCommonTools(),
      ],
    );
  }

  void showNeedTextSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('先にテキストを選択してください')),
    );
  }

  Future<void> showTextColorSheet() async {
    if (selectedItem?.type != CollageItemType.text) {
      showNeedTextSnackBar();
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('文字色を選択', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final color in textColors)
                      GestureDetector(
                        onTap: () {
                          changeSelectedTextColor(color);
                          Navigator.pop(context);
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black38),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> showFontSheet() async {
    if (selectedItem?.type != CollageItemType.text) {
      showNeedTextSnackBar();
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '書体を選択',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final font in fontOptions)
                      OutlinedButton(
                        onPressed: () {
                          changeSelectedFont(font);
                          Navigator.pop(context);
                        },
                        child: Text(
                          font.label,
                          style: TextStyle(
                            fontFamily: font.family,
                            fontWeight: font.weight,
                            fontStyle: font.style,
                            letterSpacing: font.letterSpacing,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> showStickerSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.65,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              child: Column(
                children: [
                  const Text(
                    '飾りを選択',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: stickerPresets.isEmpty
                        ? const Center(
                            child: Text('表示できる飾りがありません'),
                          )
                        : SingleChildScrollView(
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              alignment: WrapAlignment.center,
                              children: [
                                for (final sticker in stickerPresets)
                                  GestureDetector(
                                    onTap: () {
                                      addSticker(
                                        sticker['asset']!,
                                        sticker['emoji']!,
                                      );
                                      Navigator.pop(context);
                                    },
                                    child: Container(
                                      width: 62,
                                      height: 62,
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFFCF7),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.black12,
                                        ),
                                      ),
                                      child: Image.asset(
                                        sticker['asset']!,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) {
                                          return Center(
                                            child: Text(
                                              sticker['emoji']!,
                                              style: const TextStyle(
                                                fontSize: 32,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> showBackgroundColorSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('単色背景を選択', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final color in backgroundColors)
                      GestureDetector(
                        onTap: () {
                          setState(() => background = CollageBackground.color(color));
                          Navigator.pop(context);
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black26),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> showGradientBackgroundSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.55,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              child: Column(
                children: [
                  const Text(
                    'グラデーション背景を選択',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final colors in gradientBackgrounds)
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  background =
                                      CollageBackground.gradient(colors);
                                });
                                Navigator.pop(context);
                              },
                              child: Container(
                                width: 78,
                                height: 46,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(23),
                                  border: Border.all(color: Colors.black26),
                                  gradient: LinearGradient(colors: colors),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> showBackgroundImageSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.65,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              child: Column(
                children: [
                  const Text(
                    '画像背景を選択',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final asset in backgroundAssets)
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  background = CollageBackground.image(asset);
                                });
                                Navigator.pop(context);
                              },
                              child: Container(
                                width: 78,
                                height: 54,
                                clipBehavior: Clip.hardEdge,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFCF7),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.black12),
                                ),
                                child: Image.asset(
                                  asset,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) {
                                    return CustomPaint(
                                      painter: DottedBackgroundPainter(),
                                      child: const Center(
                                        child: Icon(Icons.wallpaper, size: 24),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget buildTextTools() {
    final isText = selectedItem?.type == CollageItemType.text;

    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: addTextItem,
              icon: const Icon(Icons.text_fields),
              label: const Text('テキスト追加'),
            ),
            OutlinedButton.icon(
              onPressed: isText ? editSelectedText : null,
              icon: const Icon(Icons.edit),
              label: const Text('文字編集'),
            ),
            OutlinedButton.icon(
              onPressed: isText ? showTextColorSheet : null,
              icon: const Icon(Icons.palette_outlined),
              label: const Text('文字色'),
            ),
            OutlinedButton.icon(
              onPressed: isText ? showFontSheet : null,
              icon: const Icon(Icons.font_download_outlined),
              label: const Text('書体'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        buildSelectedActions(),
        const SizedBox(height: 6),
        buildCommonTools(),
      ],
    );
  }

  Widget buildStickerTools() {
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: showStickerSheet,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('飾りを選ぶ'),
        ),
        const SizedBox(height: 10),
        buildSelectedActions(),
        const SizedBox(height: 6),
        buildCommonTools(),
      ],
    );
  }

  Widget buildBackgroundTools() {
    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: showBackgroundColorSheet,
              icon: const Icon(Icons.circle),
              label: const Text('単色'),
            ),
            OutlinedButton.icon(
              onPressed: showGradientBackgroundSheet,
              icon: const Icon(Icons.gradient),
              label: const Text('グラデーション'),
            ),
            OutlinedButton.icon(
              onPressed: showBackgroundImageSheet,
              icon: const Icon(Icons.wallpaper),
              label: const Text('画像背景'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '背景候補はボタンを押した時だけ表示されます。選ぶと自動で閉じます。',
          style: TextStyle(fontSize: 12, color: Colors.black54),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget buildEditPanel() {
    Widget child;

    switch (editTabIndex) {
      case 0:
        child = buildPhotoTools();
        break;
      case 1:
        child = buildTextTools();
        break;
      case 2:
        child = buildStickerTools();
        break;
      default:
        child = buildBackgroundTools();
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black12),
      ),
      child: child,
    );
  }

  Widget buildCanvasArea() {
    return SizedBox(
      width: displayWidth,
      height: displayHeight,
      child: Listener(
        onPointerDown: (_) {
          setState(() => isPointerOnCanvas = true);
        },
        onPointerUp: (_) {
          setState(() => isPointerOnCanvas = false);
        },
        onPointerCancel: (_) {
          setState(() => isPointerOnCanvas = false);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final canvasPoint = displayPointToCanvasPoint(details.localPosition);
            final tappedItem = hitTestItemOnCanvas(canvasPoint);
            if (tappedItem != null) {
              selectItem(tappedItem);
            }
          },
          onScaleStart: startCanvasGesture,
          onScaleUpdate: updateCanvasGesture,
          onScaleEnd: (_) => endCanvasGesture(),
          child: FittedBox(
            fit: BoxFit.contain,
            child: RepaintBoundary(
              key: captureKey,
              child: Container(
                width: canvasWidth,
                height: canvasHeight,
                clipBehavior: Clip.hardEdge,
                decoration: const BoxDecoration(),
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(child: buildBackground()),
                    for (int i = 0; i < items.length; i++)
                      buildCollageItem(items[i], i),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildSavingOverlay() {
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Container(
          color: Colors.black.withOpacity(0.35),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFCF7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 14),
                Text('保存中...', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// プリクラ風コラージュを「完成（確定）」させる。
  /// 現在の合成画像を PNG 化して onFinish に渡し、確定後に画面を閉じる。
  Future<void> finishCollage() async {
    final onFinish = widget.onFinish;
    if (onFinish == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('コラージュを完成させますか？'),
        content: const Text('完成すると、このコラージュはもう編集できなくなります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('完成させる'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      selectedIndex = -1;
      isSaving = true;
    });
    // 選択枠が消えた状態で再描画されるのを待つ
    await Future.delayed(const Duration(milliseconds: 80));

    try {
      final boundary =
          captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      await onFinish(byteData.buffer.asUint8List());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('完成に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('プリクラ風コラージュ'),
        actions: [
          // 保存ボタンは画面下のFABに一本化。
          // 「完成（確定）」は保存とは別の確定操作なので、必要な画面でのみ表示する。
          if (widget.showFinishButton && widget.onFinish != null)
            TextButton.icon(
              onPressed: finishCollage,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('完成'),
            ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            physics: isPointerOnCanvas
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                buildHeaderTip(),
                const SizedBox(height: 10),
                buildCanvasArea(),
                const SizedBox(height: 14),
                buildEditPanel(),
                const SizedBox(height: 90),
              ],
            ),
          ),
          if (isSaving) buildSavingOverlay(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: editTabIndex,
        onDestinationSelected: clearSelectionForManualTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.photo),
            label: '写真',
          ),
          NavigationDestination(
            icon: Icon(Icons.text_fields),
            label: '文字',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome),
            label: '飾り',
          ),
          NavigationDestination(
            icon: Icon(Icons.wallpaper),
            label: '背景',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: saveCollageWithoutSelection,
        icon: const Icon(Icons.save_alt),
        label: const Text('保存'),
      ),
    );
  }
}





class RotatedCropFrameClipper extends CustomClipper<Path> {
  final ItemShape shape;
  final Rect cropFrameRect;
  final double angle;

  const RotatedCropFrameClipper({
    required this.shape,
    required this.cropFrameRect,
    required this.angle,
  });

  @override
  Path getClip(Size size) {
    Path path;

    switch (shape) {
      case ItemShape.rectangle:
        path = Path()..addRect(cropFrameRect);
        break;
      case ItemShape.roundedRectangle:
        path = Path()
          ..addRRect(
            RRect.fromRectAndRadius(cropFrameRect, const Radius.circular(34)),
          );
        break;
      case ItemShape.circle:
        path = Path()..addOval(cropFrameRect);
        break;
    }

    if (angle == 0) {
      return path;
    }

    final center = cropFrameRect.center;
    final matrix = Matrix4.identity()
      ..translate(center.dx, center.dy)
      ..rotateZ(angle)
      ..translate(-center.dx, -center.dy);

    return path.transform(matrix.storage);
  }

  @override
  bool shouldReclip(covariant RotatedCropFrameClipper oldClipper) {
    return oldClipper.shape != shape ||
        oldClipper.cropFrameRect != cropFrameRect ||
        oldClipper.angle != angle;
  }
}

class PhotoShapeClipper extends CustomClipper<Path> {
  final ItemShape shape;
  final double angle;

  const PhotoShapeClipper({
    required this.shape,
    required this.angle,
  });

  @override
  Path getClip(Size size) {
    final rect = Offset.zero & size;
    Path path;

    switch (shape) {
      case ItemShape.rectangle:
        path = Path()..addRect(rect);
        break;
      case ItemShape.roundedRectangle:
        path = Path()
          ..addRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(34)),
          );
        break;
      case ItemShape.circle:
        path = Path()..addOval(rect);
        break;
    }

    if (angle == 0) {
      return path;
    }

    final center = rect.center;
    final matrix = Matrix4.identity()
      ..translate(center.dx, center.dy)
      ..rotateZ(angle)
      ..translate(-center.dx, -center.dy);

    return path.transform(matrix.storage);
  }

  @override
  bool shouldReclip(covariant PhotoShapeClipper oldClipper) {
    return oldClipper.shape != shape || oldClipper.angle != angle;
  }
}


class PhotoSelectionBorderPainter extends CustomPainter {
  final ItemShape shape;
  final double angle;
  final Color color;
  final double strokeWidth;

  const PhotoSelectionBorderPainter({
    required this.shape,
    required this.angle,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path();

    switch (shape) {
      case ItemShape.rectangle:
        path.addRect(rect.deflate(strokeWidth / 2));
        break;
      case ItemShape.roundedRectangle:
        path.addRRect(
          RRect.fromRectAndRadius(
            rect.deflate(strokeWidth / 2),
            const Radius.circular(34),
          ),
        );
        break;
      case ItemShape.circle:
        path.addOval(rect.deflate(strokeWidth / 2));
        break;
    }

    final center = rect.center;
    final matrix = Matrix4.identity()
      ..translate(center.dx, center.dy)
      ..rotateZ(angle)
      ..translate(-center.dx, -center.dy);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawPath(path.transform(matrix.storage), paint);
  }

  @override
  bool shouldRepaint(covariant PhotoSelectionBorderPainter oldDelegate) {
    return oldDelegate.shape != shape ||
        oldDelegate.angle != angle ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class OvalPhotoFramePainter extends CustomPainter {
  final Color borderColor;
  final double borderWidth;

  const OvalPhotoFramePainter({
    required this.borderColor,
    required this.borderWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shadowPaint = Paint()
      ..color = const Color(0x22000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawOval(rect.shift(const Offset(4, 6)), shadowPaint);

    final fillPaint = Paint()..color = Colors.white;
    canvas.drawOval(rect, fillPaint);

    if (borderWidth > 0) {
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..color = borderColor;
      canvas.drawOval(rect.deflate(borderWidth / 2), borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant OvalPhotoFramePainter oldDelegate) {
    return oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth;
  }
}

class DetailedCropOverlayPainter extends CustomPainter {
  final Rect cropRectNormalized;
  final ItemShape cropShape;
  final double cropAngle;

  const DetailedCropOverlayPainter({
    required this.cropRectNormalized,
    required this.cropShape,
    required this.cropAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var cropRect = Rect.fromLTWH(
      cropRectNormalized.left * size.width,
      cropRectNormalized.top * size.height,
      cropRectNormalized.width * size.width,
      cropRectNormalized.height * size.height,
    );

    Path buildCropPath(Rect rect) {
      final path = Path();
      switch (cropShape) {
        case ItemShape.rectangle:
          path.addRect(rect);
          break;
        case ItemShape.roundedRectangle:
          path.addRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(28)),
          );
          break;
        case ItemShape.circle:
          path.addOval(rect);
          break;
      }
      return path;
    }

    final center = cropRect.center;
    final matrix = Matrix4.identity()
      ..translate(center.dx, center.dy)
      ..rotateZ(cropAngle)
      ..translate(-center.dx, -center.dy);

    final cropPath = buildCropPath(cropRect).transform(matrix.storage);
    final overlayPath = Path()..addRect(Offset.zero & size);
    final darkPath = Path.combine(PathOperation.difference, overlayPath, cropPath);

    canvas.drawPath(darkPath, Paint()..color = Colors.black.withOpacity(0.52));

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.white;
    canvas.drawPath(cropPath, borderPaint);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(cropAngle);
    canvas.translate(-center.dx, -center.dy);

    final guidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withOpacity(0.72);

    if (cropShape != ItemShape.circle) {
      final dx1 = cropRect.left + cropRect.width / 3;
      final dx2 = cropRect.left + cropRect.width * 2 / 3;
      final dy1 = cropRect.top + cropRect.height / 3;
      final dy2 = cropRect.top + cropRect.height * 2 / 3;
      canvas.drawLine(Offset(dx1, cropRect.top), Offset(dx1, cropRect.bottom), guidePaint);
      canvas.drawLine(Offset(dx2, cropRect.top), Offset(dx2, cropRect.bottom), guidePaint);
      canvas.drawLine(Offset(cropRect.left, dy1), Offset(cropRect.right, dy1), guidePaint);
      canvas.drawLine(Offset(cropRect.left, dy2), Offset(cropRect.right, dy2), guidePaint);
    }

    final handlePaint = Paint()..color = Colors.white;
    const handleRadius = 5.5;
    for (final point in [
      cropRect.topLeft,
      cropRect.topRight,
      cropRect.bottomLeft,
      cropRect.bottomRight,
      cropRect.centerLeft,
      cropRect.centerRight,
      cropRect.topCenter,
      cropRect.bottomCenter,
    ]) {
      canvas.drawCircle(point, handleRadius, handlePaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DetailedCropOverlayPainter oldDelegate) {
    return oldDelegate.cropRectNormalized != cropRectNormalized ||
        oldDelegate.cropShape != cropShape ||
        oldDelegate.cropAngle != cropAngle;
  }
}

class DottedBackgroundPainter extends CustomPainter {
  const DottedBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.55);
    const gap = 42.0;

    for (double y = 18; y < size.height; y += gap) {
      for (double x = 18; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), 7, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DottedBackgroundPainter oldDelegate) => false;
}


// ##########################################################################
// コラージュ3：テンプレート型グリッドコラージュ
// ##########################################################################

enum GridSlotShape {
  rectangle,
  rounded,
  circle,
}

class GridTemplate {
  final String name;
  final String description;
  final List<GridSlot> slots;
  final Color backgroundColor;

  const GridTemplate({
    required this.name,
    required this.description,
    required this.slots,
    this.backgroundColor = const Color(0xFFF4E7D3),
  });
}

class GridSlot {
  final Rect rect;
  final GridSlotShape shape;
  final double angle;
  final double radius;

  const GridSlot({
    required this.rect,
    this.shape = GridSlotShape.rectangle,
    this.angle = 0.0,
    this.radius = 28.0,
  });
}

class GridPhotoItem {
  String? imagePath;

  int imagePixelWidth;
  int imagePixelHeight;

  double imageScale;
  double offsetX;
  double offsetY;

  // 追加：マス内写真の回転角度
  double angle;

  GridPhotoItem({
    this.imagePath,
    this.imagePixelWidth = 1,
    this.imagePixelHeight = 1,
    this.imageScale = 1.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.angle = 0.0,
  });

  bool get hasImage => imagePath != null;
}

List<GridTemplate> collage3Templates = [
  GridTemplate(
    name: 'ベーシック4分割',
    description: '一番シンプル。写真をきれいに並べたい時向け。',
    slots: [
      GridSlot(rect: Rect.fromLTWH(70, 90, 360, 430)),
      GridSlot(rect: Rect.fromLTWH(470, 90, 360, 430)),
      GridSlot(rect: Rect.fromLTWH(70, 570, 360, 430)),
      GridSlot(rect: Rect.fromLTWH(470, 570, 360, 430)),
    ],
  ),
  GridTemplate(
    name: '主役1枚＋小写真4枚',
    description: '1枚を大きく見せて、周りに思い出を添える。',
    slots: [
      GridSlot(
        rect: Rect.fromLTWH(150, 120, 600, 470),
        shape: GridSlotShape.rounded,
        radius: 36,
      ),
      GridSlot(
        rect: Rect.fromLTWH(85, 665, 250, 250),
        shape: GridSlotShape.circle,
      ),
      GridSlot(
        rect: Rect.fromLTWH(365, 640, 220, 300),
        shape: GridSlotShape.rounded,
      ),
      GridSlot(
        rect: Rect.fromLTWH(615, 665, 250, 250),
        shape: GridSlotShape.circle,
      ),
      GridSlot(
        rect: Rect.fromLTWH(260, 925, 380, 120),
        shape: GridSlotShape.rounded,
      ),
    ],
  ),
  GridTemplate(
    name: '縦長ポスター',
    description: '縦写真が多い時に使いやすい。',
    slots: [
      GridSlot(
        rect: Rect.fromLTWH(70, 80, 250, 720),
        shape: GridSlotShape.rounded,
      ),
      GridSlot(rect: Rect.fromLTWH(350, 80, 250, 360)),
      GridSlot(
        rect: Rect.fromLTWH(630, 80, 200, 360),
        shape: GridSlotShape.rounded,
      ),
      GridSlot(rect: Rect.fromLTWH(350, 470, 480, 330)),
      GridSlot(
        rect: Rect.fromLTWH(120, 835, 660, 190),
        shape: GridSlotShape.rounded,
      ),
    ],
  ),
  GridTemplate(
    name: '横長バナー',
    description: '横長写真や景色をまとめたい時向け。',
    slots: [
      GridSlot(
        rect: Rect.fromLTWH(60, 90, 780, 260),
        shape: GridSlotShape.rounded,
      ),
      GridSlot(rect: Rect.fromLTWH(60, 390, 370, 260)),
      GridSlot(rect: Rect.fromLTWH(470, 390, 370, 260)),
      GridSlot(
        rect: Rect.fromLTWH(60, 690, 240, 300),
        shape: GridSlotShape.rounded,
      ),
      GridSlot(
        rect: Rect.fromLTWH(330, 690, 240, 300),
        shape: GridSlotShape.rounded,
      ),
      GridSlot(
        rect: Rect.fromLTWH(600, 690, 240, 300),
        shape: GridSlotShape.rounded,
      ),
    ],
  ),
  GridTemplate(
    name: '丸フォト',
    description: '丸い写真で柔らかい印象にする。',
    slots: [
      GridSlot(
        rect: Rect.fromLTWH(115, 95, 260, 260),
        shape: GridSlotShape.circle,
      ),
      GridSlot(
        rect: Rect.fromLTWH(525, 95, 260, 260),
        shape: GridSlotShape.circle,
      ),
      GridSlot(
        rect: Rect.fromLTWH(320, 360, 260, 260),
        shape: GridSlotShape.circle,
      ),
      GridSlot(
        rect: Rect.fromLTWH(115, 625, 260, 260),
        shape: GridSlotShape.circle,
      ),
      GridSlot(
        rect: Rect.fromLTWH(525, 625, 260, 260),
        shape: GridSlotShape.circle,
      ),
    ],
  ),
  GridTemplate(
    name: '角丸ムードボード',
    description: '余白多めで、Pinterestっぽく見せる。',
    backgroundColor: Color(0xFFF7EFE4),
    slots: [
      GridSlot(
        rect: Rect.fromLTWH(80, 90, 330, 260),
        shape: GridSlotShape.rounded,
      ),
      GridSlot(
        rect: Rect.fromLTWH(490, 90, 330, 360),
        shape: GridSlotShape.rounded,
      ),
      GridSlot(
        rect: Rect.fromLTWH(80, 400, 330, 420),
        shape: GridSlotShape.rounded,
      ),
      GridSlot(
        rect: Rect.fromLTWH(490, 500, 330, 250),
        shape: GridSlotShape.rounded,
      ),
      GridSlot(
        rect: Rect.fromLTWH(230, 850, 440, 170),
        shape: GridSlotShape.rounded,
      ),
    ],
  ),
  GridTemplate(
    name: 'ハート型',
    description: '記念日・好きな写真まとめ向け。',
    backgroundColor: Color(0xFFFFE4EC),
    slots: [
      GridSlot(
        rect: Rect.fromLTWH(250, 105, 190, 190),
        shape: GridSlotShape.circle,
      ),
      GridSlot(
        rect: Rect.fromLTWH(460, 105, 190, 190),
        shape: GridSlotShape.circle,
      ),
      GridSlot(
        rect: Rect.fromLTWH(155, 270, 190, 190),
        shape: GridSlotShape.circle,
      ),
      GridSlot(
        rect: Rect.fromLTWH(355, 285, 190, 190),
        shape: GridSlotShape.circle,
      ),
      GridSlot(
        rect: Rect.fromLTWH(555, 270, 190, 190),
        shape: GridSlotShape.circle,
      ),
      GridSlot(
        rect: Rect.fromLTWH(240, 470, 190, 190),
        shape: GridSlotShape.circle,
      ),
      GridSlot(
        rect: Rect.fromLTWH(470, 470, 190, 190),
        shape: GridSlotShape.circle,
      ),
      GridSlot(
        rect: Rect.fromLTWH(350, 660, 200, 200),
        shape: GridSlotShape.circle,
      ),
    ],
  ),
  GridTemplate(
    name: '雑誌風ミックス',
    description: '大きさ違いでメリハリを出す。',
    slots: [
      GridSlot(
        rect: Rect.fromLTWH(70, 80, 500, 360),
        shape: GridSlotShape.rounded,
        angle: -0.025,
      ),
      GridSlot(
        rect: Rect.fromLTWH(600, 110, 230, 300),
        angle: 0.035,
      ),
      GridSlot(
        rect: Rect.fromLTWH(90, 500, 250, 390),
        angle: 0.025,
      ),
      GridSlot(
        rect: Rect.fromLTWH(380, 480, 450, 250),
        shape: GridSlotShape.rounded,
      ),
      GridSlot(
        rect: Rect.fromLTWH(400, 765, 200, 200),
        shape: GridSlotShape.circle,
      ),
      GridSlot(
        rect: Rect.fromLTWH(630, 760, 200, 250),
        shape: GridSlotShape.rounded,
        angle: -0.035,
      ),
    ],
  ),
  GridTemplate(
    name: '3×3グリッド',
    description: '写真数が多い時の定番。',
    slots: [
      for (int row = 0; row < 3; row++)
        for (int col = 0; col < 3; col++)
          GridSlot(
            rect: Rect.fromLTWH(
              70 + col * 260,
              120 + row * 290,
              230,
              250,
            ),
            shape: GridSlotShape.rounded,
            radius: 24,
          ),
    ],
  ),
  GridTemplate(
    name: 'ダイヤ風アクセント',
    description: '少し個性的。タイル感を出したい時向け。',
    backgroundColor: Color(0xFFEAF2F7),
    slots: [
      GridSlot(rect: Rect.fromLTWH(340, 80, 220, 220), angle: 0.785),
      GridSlot(rect: Rect.fromLTWH(165, 270, 220, 220), angle: 0.785),
      GridSlot(rect: Rect.fromLTWH(515, 270, 220, 220), angle: 0.785),
      GridSlot(rect: Rect.fromLTWH(340, 460, 220, 220), angle: 0.785),
      GridSlot(rect: Rect.fromLTWH(165, 650, 220, 220), angle: 0.785),
      GridSlot(rect: Rect.fromLTWH(515, 650, 220, 220), angle: 0.785),
    ],
  ),
];

class GridCollagePage extends StatefulWidget {
  final List<PhotoPin> availablePins;
  final int? initialColorId;

  const GridCollagePage({
    super.key,
    this.availablePins = const [],
    this.initialColorId,
  });

  @override
  State<GridCollagePage> createState() => _GridCollagePageState();
}

class _GridCollagePageState extends State<GridCollagePage> {
  static const double canvasWidth = 900.0;
  static const double canvasHeight = 1100.0;
  static const double displayWidth = 320.0;

  final GlobalKey captureKey = GlobalKey();

  int selectedTemplateIndex = 0;
  int selectedSlotIndex = -1;

  late List<GridPhotoItem> photos;

  bool isCropOverlayOpen = false;
  bool isLoadingCropImage = false;

  bool isSavingGridCollage = false;

  int croppingSlotIndex = -1;

  double editingImageScale = 1.0;
  double editingOffsetX = 0.0;
  double editingOffsetY = 0.0;
  double editingAngle = 0.0;

  double startEditingScale = 1.0;
  double startEditingAngle = 0.0;
  double startEditingOffsetX = 0.0;
  double startEditingOffsetY = 0.0;
  Offset startEditingFocalPoint = Offset.zero;

  int editingImagePixelWidth = 1;
  int editingImagePixelHeight = 1;

  GridTemplate get template => collage3Templates[selectedTemplateIndex];

  @override
  void initState() {
    super.initState();
    photos = createPhotoItemsForTemplate(template);
  }

  List<GridPhotoItem> createPhotoItemsForTemplate(GridTemplate template) {
    return List.generate(
      template.slots.length,
      (_) => GridPhotoItem(),
    );
  }

  void changeTemplate(int index) {
    setState(() {
      selectedTemplateIndex = index;
      selectedSlotIndex = -1;
      photos = createPhotoItemsForTemplate(collage3Templates[index]);
      isCropOverlayOpen = false;
    });
  }

  Future<void> pickPhotoForSlot(int index) async {
    if (widget.availablePins.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('選択できる写真がありません')),
      );
      return;
    }

    final selectedPins = await showAppPhotoPicker(
      context: context,
      pins: widget.availablePins,
      multiSelect: false,
    );

    if (selectedPins == null || selectedPins.isEmpty) return;

    final pin = selectedPins.first;
    final imageSize = await getImagePixelSizeFromFile(pin.imagePath);

    if (!mounted) return;

    setState(() {
      selectedSlotIndex = index;
      photos[index] = GridPhotoItem(
        imagePath: pin.imagePath,
        imagePixelWidth: imageSize.width.toInt(),
        imagePixelHeight: imageSize.height.toInt(),
        imageScale: 1.0,
        offsetX: 0.0,
        offsetY: 0.0,
        angle: 0.0,
      );
    });

    openCropOverlay(index);
  }

  void selectSlot(int index) {
    setState(() {
      selectedSlotIndex = index;
    });
  }

  void deleteSelectedSlotPhoto() {
    if (selectedSlotIndex < 0 || selectedSlotIndex >= photos.length) return;

    setState(() {
      photos[selectedSlotIndex] = GridPhotoItem();
    });
  }

  Future<void> saveGridCollageWithoutSelection() async {
    if (isSavingGridCollage) return;

    final int oldSelectedSlotIndex = selectedSlotIndex;

    setState(() {
        isSavingGridCollage = true;
        selectedSlotIndex = -1;
    });

    // 選択枠が消えた状態で再描画されるのを待つ
    await Future.delayed(const Duration(milliseconds: 80));

    if (!mounted) return;

    await saveWidgetToGallery(
        context: context,
        repaintKey: captureKey,
        fileNamePrefix: 'grid_collage',
    );

    if (!mounted) return;

    setState(() {
        selectedSlotIndex = oldSelectedSlotIndex;
        isSavingGridCollage = false;
    });
  }

  Future<void> openCropOverlay(int index) async {
    if (index < 0 || index >= photos.length) return;

    final photo = photos[index];
    if (!photo.hasImage) return;

    setState(() {
      selectedSlotIndex = index;
      croppingSlotIndex = index;
      isCropOverlayOpen = true;
      isLoadingCropImage = true;

      editingImageScale = photo.imageScale;
      editingOffsetX = photo.offsetX;
      editingOffsetY = photo.offsetY;
      editingAngle = photo.angle;
    });

    try {
      final bytes = await File(photo.imagePath!).readAsBytes();
      final decoded = img.decodeImage(bytes);

      if (decoded == null) {
        throw Exception('画像を読み込めませんでした');
      }

      if (!mounted) return;

      setState(() {
        editingImagePixelWidth = decoded.width;
        editingImagePixelHeight = decoded.height;

        photos[index].imagePixelWidth = decoded.width;
        photos[index].imagePixelHeight = decoded.height;

        isLoadingCropImage = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isCropOverlayOpen = false;
        isLoadingCropImage = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('画像の読み込みに失敗しました: $e'),
        ),
      );
    }
  }

  double getEditFrameWidth(GridSlot slot) {
    final frameWidth = slot.rect.width * displayWidth / canvasWidth;
    final frameHeight = slot.rect.height * displayWidth / canvasWidth;

    double editFrameWidth = frameWidth;
    double editFrameHeight = frameHeight;

    const minSide = 180.0;
    final currentMinSide = min(editFrameWidth, editFrameHeight).toDouble();

    if (currentMinSide < minSide) {
      final scale = minSide / currentMinSide;
      editFrameWidth *= scale;
      editFrameHeight *= scale;
    }

    const maxSide = 310.0;
    final currentMaxSide = max(editFrameWidth, editFrameHeight).toDouble();

    if (currentMaxSide > maxSide) {
      final scale = maxSide / currentMaxSide;
      editFrameWidth *= scale;
      editFrameHeight *= scale;
    }

    return editFrameWidth;
  }

  double getEditFrameHeight(GridSlot slot) {
    final frameWidth = slot.rect.width * displayWidth / canvasWidth;
    final frameHeight = slot.rect.height * displayWidth / canvasWidth;

    double editFrameWidth = frameWidth;
    double editFrameHeight = frameHeight;

    const minSide = 180.0;
    final currentMinSide = min(editFrameWidth, editFrameHeight).toDouble();

    if (currentMinSide < minSide) {
      final scale = minSide / currentMinSide;
      editFrameWidth *= scale;
      editFrameHeight *= scale;
    }

    const maxSide = 310.0;
    final currentMaxSide = max(editFrameWidth, editFrameHeight).toDouble();

    if (currentMaxSide > maxSide) {
      final scale = maxSide / currentMaxSide;
      editFrameWidth *= scale;
      editFrameHeight *= scale;
    }

    return editFrameHeight;
  }

  Size calculateCoverImageSize({
    required double imageAspect,
    required double frameWidth,
    required double frameHeight,
    required double imageScale,
  }) {
    final frameAspect = frameWidth / frameHeight;

    double baseImageWidth;
    double baseImageHeight;

    if (imageAspect > frameAspect) {
      baseImageHeight = frameHeight;
      baseImageWidth = baseImageHeight * imageAspect;
    } else {
      baseImageWidth = frameWidth;
      baseImageHeight = baseImageWidth / imageAspect;
    }

    return Size(
      baseImageWidth * imageScale,
      baseImageHeight * imageScale,
    );
  }

  void clampEditingOffset({
    required double frameWidth,
    required double frameHeight,
  }) {
    final imageAspect = editingImagePixelWidth / editingImagePixelHeight;

    final imageSize = calculateCoverImageSize(
      imageAspect: imageAspect,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      imageScale: editingImageScale,
    );

    final maxOffsetX = max((imageSize.width - frameWidth) / 2, 0.0).toDouble();
    final maxOffsetY =
        max((imageSize.height - frameHeight) / 2, 0.0).toDouble();

    editingOffsetX = editingOffsetX.clamp(-maxOffsetX, maxOffsetX).toDouble();
    editingOffsetY = editingOffsetY.clamp(-maxOffsetY, maxOffsetY).toDouble();
  }

  void moveEditingImage({
    required Offset deltaOnScreen,
    required double frameWidth,
    required double frameHeight,
  }) {
    setState(() {
      editingOffsetX += deltaOnScreen.dx;
      editingOffsetY += deltaOnScreen.dy;

      clampEditingOffset(
        frameWidth: frameWidth,
        frameHeight: frameHeight,
      );
    });
  }

  void zoomEditingImage(double delta) {
    if (croppingSlotIndex < 0 || croppingSlotIndex >= photos.length) return;

    final slot = template.slots[croppingSlotIndex];
    final frameWidth = getEditFrameWidth(slot);
    final frameHeight = getEditFrameHeight(slot);

    setState(() {
      final oldScale = editingImageScale;

      editingImageScale = (editingImageScale + delta)
          .clamp(1.0, 4.0)
          .toDouble();

      if (editingImageScale == oldScale) return;

      final scaleRatio = editingImageScale / oldScale;

      editingOffsetX *= scaleRatio;
      editingOffsetY *= scaleRatio;

      clampEditingOffset(
        frameWidth: frameWidth,
        frameHeight: frameHeight,
      );
    });
  }

  void applyCropOverlay() {
    if (croppingSlotIndex < 0 || croppingSlotIndex >= photos.length) return;

    setState(() {
      photos[croppingSlotIndex].imageScale = editingImageScale;
      photos[croppingSlotIndex].offsetX = editingOffsetX;
      photos[croppingSlotIndex].offsetY = editingOffsetY;
      photos[croppingSlotIndex].angle = editingAngle;

      isCropOverlayOpen = false;
      isLoadingCropImage = false;
      croppingSlotIndex = -1;
    });
  }

  void closeCropOverlay() {
    setState(() {
      isCropOverlayOpen = false;
      isLoadingCropImage = false;
      croppingSlotIndex = -1;
    });
  }

  Widget buildGridSlot(int index) {
    final slot = template.slots[index];
    final photo = photos[index];
    final isSelected = index == selectedSlotIndex;

    return Positioned(
        left: slot.rect.left,
        top: slot.rect.top,
        width: slot.rect.width,
        height: slot.rect.height,
        child: Transform.rotate(
        angle: slot.angle,
        child: GestureDetector(
            onTap: () {
            if (photo.hasImage) {
                selectSlot(index);
            } else {
                pickPhotoForSlot(index);
            }
            },
            child: Stack(
            clipBehavior: Clip.none,
            children: [
                // 写真本体
                ClipPath(
                clipper: GridSlotClipper(
                    shape: slot.shape,
                    radius: slot.radius,
                ),
                child: Container(
                    width: slot.rect.width,
                    height: slot.rect.height,
                    color: photo.hasImage
                        ? Colors.white
                        : Colors.white.withOpacity(0.55),
                    child: photo.hasImage
                        ? buildSlotImage(
                            photo: photo,
                            slot: slot,
                        )
                        : buildEmptySlot(index),
                ),
                ),

                // 通常時の白い枠
                Positioned.fill(
                child: IgnorePointer(
                    child: CustomPaint(
                    painter: GridSlotBorderPainter(
                        shape: slot.shape,
                        radius: slot.radius,
                        color: Colors.white,
                        strokeWidth: 6,
                    ),
                    ),
                ),
                ),

                // 選択中の青い枠
                if (isSelected)
                Positioned.fill(
                    child: IgnorePointer(
                    child: CustomPaint(
                        painter: GridSlotBorderPainter(
                        shape: slot.shape,
                        radius: slot.radius,
                        color: Colors.blueAccent,
                        strokeWidth: 8,
                        ),
                    ),
                    ),
                ),
            ],
            ),
        ),
        ),
    );
  }

  Widget buildSlotImage({
    required GridPhotoItem photo,
    required GridSlot slot,
  }) {
    final imageAspect = photo.imagePixelWidth / photo.imagePixelHeight;

    final imageSize = calculateCoverImageSize(
      imageAspect: imageAspect,
      frameWidth: slot.rect.width,
      frameHeight: slot.rect.height,
      imageScale: photo.imageScale,
    );

    final editFrameWidth = getEditFrameWidth(slot);
    final editFrameHeight = getEditFrameHeight(slot);

    final scaleX = slot.rect.width / editFrameWidth;
    final scaleY = slot.rect.height / editFrameHeight;

    final imageLeft =
        (slot.rect.width - imageSize.width) / 2 + photo.offsetX * scaleX;

    final imageTop =
        (slot.rect.height - imageSize.height) / 2 + photo.offsetY * scaleY;

    return SizedBox(
      width: slot.rect.width,
      height: slot.rect.height,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: imageLeft,
            top: imageTop,
            width: imageSize.width,
            height: imageSize.height,
            child: Transform.rotate(
              angle: photo.angle,
              child: Image.file(
                File(photo.imagePath!),
                width: imageSize.width,
                height: imageSize.height,
                fit: BoxFit.fill,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildEmptySlot(int index) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.add_photo_alternate_outlined,
            size: 54,
            color: Colors.black38,
          ),
          const SizedBox(height: 8),
          Text(
            '${index + 1}',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black26,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSlotActions() {
    final hasSelection =
        selectedSlotIndex >= 0 && selectedSlotIndex < photos.length;

    return Column(
        children: [
        if (isSavingGridCollage)
            const Text(
            '保存中...',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
            ),
            )
        else if (!hasSelection)
            const Text(
            'マスをタップして写真を選択',
            style: TextStyle(fontSize: 12),
            ),
        if (hasSelection) ...[
          Text(
            '選択中：${selectedSlotIndex + 1}番目のマス',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => pickPhotoForSlot(selectedSlotIndex),
                icon: const Icon(Icons.photo_library),
                label: Text(
                  photos[selectedSlotIndex].hasImage ? '写真変更' : '写真選択',
                ),
              ),
              OutlinedButton.icon(
                onPressed: photos[selectedSlotIndex].hasImage
                    ? () => openCropOverlay(selectedSlotIndex)
                    : null,
                icon: const Icon(Icons.crop),
                label: const Text('トリミング'),
              ),
              OutlinedButton.icon(
                onPressed: photos[selectedSlotIndex].hasImage
                    ? deleteSelectedSlotPhoto
                    : null,
                icon: const Icon(Icons.delete_outline),
                label: const Text('削除'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: saveGridCollageWithoutSelection,
          icon: const Icon(Icons.save_alt),
          label: const Text('保存'),
        ),
      ],
    );
  }

  Widget buildCropOverlay() {
    if (croppingSlotIndex < 0 || croppingSlotIndex >= photos.length) {
      return const SizedBox.shrink();
    }

    final photo = photos[croppingSlotIndex];
    if (!photo.hasImage) return const SizedBox.shrink();

    final slot = template.slots[croppingSlotIndex];

    final editFrameWidth = getEditFrameWidth(slot);
    final editFrameHeight = getEditFrameHeight(slot);

    final imageAspect = editingImagePixelWidth / editingImagePixelHeight;

    final imageSize = calculateCoverImageSize(
      imageAspect: imageAspect,
      frameWidth: editFrameWidth,
      frameHeight: editFrameHeight,
      imageScale: editingImageScale,
    );

    final imageLeft =
        (editFrameWidth - imageSize.width) / 2 + editingOffsetX;

    final imageTop =
        (editFrameHeight - imageSize.height) / 2 + editingOffsetY;

    final screenWidth = MediaQuery.of(context).size.width;
    final overlayWidth = min(screenWidth - 24, 360).toDouble();

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.42),
        alignment: Alignment.center,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: overlayWidth,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFCF7),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: isLoadingCropImage
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('画像を読み込み中...'),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'トリミング',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: closeCropOverlay,
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          width: editFrameWidth,
                          height: editFrameHeight,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            border: Border.all(
                              color: Colors.white,
                              width: 4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 10,
                                offset: const Offset(4, 4),
                              ),
                            ],
                          ),
                          child: ClipPath(
                            clipper: GridSlotClipper(
                              shape: slot.shape,
                              radius:
                                  slot.radius * editFrameWidth / slot.rect.width,
                            ),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onScaleStart: (details) {
                                startEditingScale = editingImageScale;
                                startEditingAngle = editingAngle;
                                startEditingOffsetX = editingOffsetX;
                                startEditingOffsetY = editingOffsetY;
                                startEditingFocalPoint = details.localFocalPoint;
                              },
                              onScaleUpdate: (details) {
                                setState(() {
                                  editingImageScale = (startEditingScale * details.scale)
                                      .clamp(1.0, 4.0)
                                      .toDouble();

                                  editingAngle = startEditingAngle + details.rotation;

                                  editingOffsetX =
                                      startEditingOffsetX + details.localFocalPoint.dx - startEditingFocalPoint.dx;
                                  editingOffsetY =
                                      startEditingOffsetY + details.localFocalPoint.dy - startEditingFocalPoint.dy;

                                  clampEditingOffset(
                                    frameWidth: editFrameWidth,
                                    frameHeight: editFrameHeight,
                                  );
                                });
                              },
                              child: Stack(
                                clipBehavior: Clip.hardEdge,
                                children: [
                                  Positioned(
                                    left: imageLeft,
                                    top: imageTop,
                                    width: imageSize.width,
                                    height: imageSize.height,
                                    child: Transform.rotate(
                                      angle: editingAngle,
                                      child: Image.file(
                                        File(photo.imagePath!),
                                        width: imageSize.width,
                                        height: imageSize.height,
                                        fit: BoxFit.fill,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          OutlinedButton(
                            onPressed: () => zoomEditingImage(0.08),
                            child: const Text('画像を拡大'),
                          ),
                          OutlinedButton(
                            onPressed: () => zoomEditingImage(-0.08),
                            child: const Text('画像を縮小'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '画像をドラッグして位置を調整',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton(
                            onPressed: closeCropOverlay,
                            child: const Text('キャンセル'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: applyCropOverlay,
                            child: const Text('完了'),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget buildSavingOverlay() {
    return Positioned.fill(
        child: AbsorbPointer(
        absorbing: true,
        child: Container(
            color: Colors.black.withOpacity(0.35),
            alignment: Alignment.center,
            child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 20,
            ),
            decoration: BoxDecoration(
                color: const Color(0xFFFFFCF7),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                ),
                ],
            ),
            child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                CircularProgressIndicator(),
                SizedBox(height: 14),
                Text(
                    '保存中...',
                    style: TextStyle(
                    fontWeight: FontWeight.bold,
                    ),
                ),
                ],
            ),
            ),
        ),
        ),
    );
    }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('コラージュ3：テンプレート'),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'グリッドを選ぶ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 94,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: collage3Templates.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final currentTemplate = collage3Templates[index];
                      final isSelected = index == selectedTemplateIndex;

                      return GestureDetector(
                        onTap: () => changeTemplate(index),
                        child: Container(
                          width: 140,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.black87 : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.black87
                                  : Colors.black26,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentTemplate.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${currentTemplate.slots.length}枚',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isSelected
                                      ? Colors.white70
                                      : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  template.description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: displayWidth,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: RepaintBoundary(
                      key: captureKey,
                      child: Container(
                        width: canvasWidth,
                        height: canvasHeight,
                        color: template.backgroundColor,
                        child: Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            for (int i = 0; i < template.slots.length; i++)
                              buildGridSlot(i),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                buildSlotActions(),
              ],
            ),
          ),
          if (isCropOverlayOpen) buildCropOverlay(),
          if (isSavingGridCollage) buildSavingOverlay(),
        ],
      ),
    );
  }
}

class GridSlotClipper extends CustomClipper<Path> {
  final GridSlotShape shape;
  final double radius;

  GridSlotClipper({
    required this.shape,
    required this.radius,
  });

  @override
  Path getClip(Size size) {
    final rect = Offset.zero & size;

    switch (shape) {
      case GridSlotShape.rectangle:
        return Path()..addRect(rect);
      case GridSlotShape.rounded:
        return Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              rect,
              Radius.circular(radius),
            ),
          );
      case GridSlotShape.circle:
        return Path()..addOval(rect);
    }
  }

  @override
  bool shouldReclip(covariant GridSlotClipper oldClipper) {
    return oldClipper.shape != shape || oldClipper.radius != radius;
  }
}

class GridSlotBorderPainter extends CustomPainter {
  final GridSlotShape shape;
  final double radius;
  final Color color;
  final double strokeWidth;

  GridSlotBorderPainter({
    required this.shape,
    required this.radius,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;

    switch (shape) {
      case GridSlotShape.rectangle:
        canvas.drawRect(rect.deflate(strokeWidth / 2), paint);
        break;

      case GridSlotShape.rounded:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect.deflate(strokeWidth / 2),
            Radius.circular(radius),
          ),
          paint,
        );
        break;

      case GridSlotShape.circle:
        canvas.drawOval(
          rect.deflate(strokeWidth / 2),
          paint,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant GridSlotBorderPainter oldDelegate) {
    return oldDelegate.shape != shape ||
        oldDelegate.radius != radius ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}