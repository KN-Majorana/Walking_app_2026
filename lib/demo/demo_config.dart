import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// ═══════════════════════════════════════════════════════════════════
/// 対戦機能デモの設定値（座標・色・スケジュール）。
///
/// このデモは integration_Ver1 の「対戦機能」を 1 台の端末だけで説明する
/// ためのもの。Firebase / GPS / 実カメラ / 色判定(OpenCV) は一切使わず、
/// challenger（青）と opponent（赤）の両方をこの設定に沿って自動再生する。
///
/// 色 ID は color_extraction.dart の colorPaletteBattle のインデックスに
/// 合わせている（VersusPolygonsOverlay がこの ID で色を塗るため）:
///   0 = Red, 6 = Blue
/// ═══════════════════════════════════════════════════════════════════
class DemoConfig {
  DemoConfig._();

  // ── プレイヤー識別子（デモ内の擬似 UID）──
  static const String challengerUid = 'challenger';
  static const String opponentUid = 'opponent';

  // ── 色（colorPaletteBattle のインデックス）──
  static const int challengerColorId = 6; // Blue
  static const int opponentColorId = 0; // Red

  // colorPaletteBattle と同じ RGB（バー・マーカー表示用）
  static const Color challengerColor = Color.fromRGBO(0, 150, 255, 1); // 青
  static const Color opponentColor = Color.fromRGBO(255, 0, 0, 1); // 赤

  // ── スタート地点（両者共通）──
  static const LatLng start = LatLng(35.1605614, 136.8980553);

  // ── challenger（青）が通るルート ──
  static const List<LatLng> challengerRoute = [
    LatLng(35.1611499, 136.9008229), // 1
    LatLng(35.1597906, 136.9033574), // 2
    LatLng(35.158691, 136.9017606), // 3
  ];

  // ── opponent（赤）が通るルート ──
  static const List<LatLng> opponentRoute = [
    LatLng(35.1597604, 136.8994269), // 1
    LatLng(35.1591477, 136.9000865), // 2
    LatLng(35.1607347, 136.9021001), // 3
  ];

  // 各座標に到達したときに「起動したカメラ」で表示する写真。
  static const List<String> challengerPhotos = [
    'assets/demo_photos/blue_1.png',
    'assets/demo_photos/blue_2.png',
    'assets/demo_photos/blue_3.png',
  ];
  static const List<String> opponentPhotos = [
    'assets/demo_photos/red_1.png',
    'assets/demo_photos/red_2.png',
    'assets/demo_photos/red_3.png',
  ];

  // ── スケジュール（対戦開始からの経過「デモ秒」）──
  //   各プレイヤーが各座標へ到達し、写真ピンを刺す時刻。
  //   ピンを刺す順番（＝到達順）が
  //     red_1 → blue_1 → red_2 → blue_2 → red_3 → blue_3
  //   になるよう、赤が各地点へ先に到達するよう並べてある。
  //   よって 5番目(red_3=720s)で赤の三角形、6番目(blue_3=840s)で青の三角形が
  //   確定し、青（後から主張）が重なりを塗り返す。
  static const List<double> opponentArrivalSec = [180, 450, 720];
  static const List<double> challengerArrivalSec = [240, 540, 840];

  /// 対戦の制限時間（デモ秒）。15 分。
  static const double battleLimitSec = 900;

  /// challenger が 3 枚目（blue_3）を刺してから対決終了までの待ち時間。
  /// blue_3 は 840s なので 840 + 60 = 900s ＝ 制限時間ちょうどに終了する。
  static const double endDelayAfterLastSec = 60;

  // ── 地図の初期表示 ──
  static const LatLng mapCenter = LatLng(35.1599, 136.9006);
  static const double mapZoom = 15.2;
}
