# 散歩マップアプリ 説明書

## 概要

地図上に自分が歩いた軌跡を記録し、撮った写真をピンとして残せる Flutter 製モバイルアプリ。歩いた範囲だけ霧が晴れていく「霧モード」や、過去の散歩を地図上で再生する「再生モード」、撮影写真の代表色を使ったフィルタリング・コラージュ作成機能を備える。

- **アプリ名（内部）**: `test`（`pubspec.yaml`）／表示タイトル: `Mobility App`
- **バージョン**: 1.0.0+1
- **対象プラットフォーム**: Android / iOS（`linux/` `macos/` `windows/` `web/` も生成済みだが主は iOS・Android）
- **言語**: 日本語 UI

---

## 主な機能

### 1. 散歩の軌跡記録（通常モード）
- 「散歩開始」ボタンで現在地の取得を開始し、`geolocator` の位置ストリーム（距離フィルタ 5m）で軌跡点を蓄積する。
- 経過時間と記録点数がカード UI に表示される。
- 「停止」で `WalkTrack` として `shared_preferences` に永続保存される。

### 2. 霧モード（Fog Mode）
- 地図全体を半透明の黒い霧で覆い、過去に歩いた軌跡点から半径 30m の範囲だけが透明に晴れる。
- `FogOverlay`（`CustomPainter`）が `MapCamera` の座標変換を使って画面上の晴れ領域を描画。
- 「探索しきった地図」を可視化するための演出機能。

### 3. 再生モード（Animation Mode）
- 保存済みの散歩記録を選び、地図上にゴーストマーカー（緑の発光円）を出して当時の歩行を 4 倍速で再生する。
- `GhostTrack` が経過時間に対する位置を線形補間で算出する純粋計算クラス。タイマー駆動は `MapScreen` 側。

### 4. 写真ピン
- 撮影ボタンでカメラを起動（`image_picker`）し、現在地の緯度経度と一緒に写真を保存する。
- 撮影時に **OpenCV（`opencv_dart`）で代表色を最大 3 色抽出** し、写真と一緒に `sqflite` に保存する。
- 地図上には円形にトリミングされたサムネイル（`PhotoPinMarker`）が表示され、タップで詳細シートが開く。

### 5. 写真一覧 & コラージュ
- 一覧画面（`PhotoListScreen`）で全写真をグリッド表示。代表色での絞り込み可能。
- 3 種類のコラージュ生成（`collage_module.dart`、3300 行）:
  - **自動配置コラージュ**（`AutoCollagePage`）: スクラップブック風に自動でレイアウト
  - **自由配置コラージュ**（`EditableCollagePage`）: 写真をドラッグ・トリミングして自由配置
  - **テンプレート型グリッドコラージュ**（`GridCollagePage`）: 定型グリッドに写真をはめ込む
- 完成したコラージュは `screenshot` パッケージで画像化し、`image_gallery_saver_plus` で端末のフォトライブラリに保存。

---

## 画面構成

```
MyApp (main.dart)
 └─ MapScreen ── メイン画面（地図 + モード切替 + 各種コントロール）
     ├─ FlutterMap（国土地理院タイル等）
     │   ├─ TileLayer
     │   ├─ PolylineLayer（軌跡描画）
     │   ├─ MarkerLayer（現在地・写真ピン・ゴースト）
     │   └─ FogOverlay（霧モード時のみ）
     ├─ ModeSwitcher（通常 / 霧 / 再生 の切替）
     ├─ RecordingControls（記録の開始・停止と経過表示）
     ├─ TrackPickerSheet（再生モードで軌跡を選ぶ）
     ├─ PhotoDetailSheet（写真ピンの詳細）
     └─ PhotoListScreen → AutoCollage / EditableCollage / GridCollage
```

---

## ファイル構成（`lib/`）

| ファイル | 役割 |
|---|---|
| `main.dart` | エントリポイント。`MaterialApp` 起動のみ |
| `map_screen.dart` | メイン画面。地図・モード制御・記録ロジックの統合点 |
| `map_mode.dart` | `MapMode` enum（normal / fog / animation） |
| `walk_track.dart` | 散歩データモデル（`TrackPoint`, `WalkTrack`）と JSON 変換 |
| `track_storage_service.dart` | `shared_preferences` への軌跡永続化 |
| `location_service.dart` | `geolocator` ラッパー（権限処理 + 単発取得 / ストリーム） |
| `recording_controls.dart` | 記録ステータス UI（散歩中／停止中の表示） |
| `mode_switcher.dart` | 3 モード切替トグル UI |
| `track_picker_sheet.dart` | 過去軌跡選択ボトムシート |
| `ghost_track.dart` | 再生モード用、経過時間→位置の補間計算 |
| `ghost_marker.dart` | ゴースト位置マーカー Widget |
| `current_location_marker.dart` | 現在地マーカー Widget |
| `fog_clearing_service.dart` | 「点が晴れ範囲内か」の距離判定ロジック |
| `fog_overlay.dart` | 霧描画レイヤー（`CustomPainter`） |
| `photo_pin.dart` | 写真ピンのデータモデル |
| `photo_service.dart` | 撮影〜保存〜読込までのファサード |
| `photo_pin_marker.dart` | 地図上の円形写真サムネイル |
| `photo_detail_sheet.dart` | 写真タップ時の詳細表示シート |
| `photo_list_screen.dart` | 写真グリッド一覧 + コラージュ起動 |
| `color_module.dart` | OpenCV による代表色抽出 + `sqflite` 保存 |
| `collage_module.dart` | 3 種コラージュ画面（自動 / 自由 / テンプレ）|

---

## 主要パッケージ

| パッケージ | 用途 |
|---|---|
| `flutter_map` ^7.0.2 | 地図表示。OpenStreetMap 互換のタイルレイヤ |
| `latlong2` ^0.9.1 | 緯度経度モデルと距離計算 |
| `geolocator` ^14.0.3 | 位置情報の取得・ストリーム |
| `shared_preferences` ^2.2.2 | 軌跡データの永続化 |
| `sqflite` ^2.4.2 | 写真メタデータ・代表色の DB 保存 |
| `image_picker` ^1.2.2 | カメラ起動・写真取得 |
| `opencv_dart` ^2.2.1+4 | 写真からの代表色抽出 |
| `image` ^4.9.1 | 画像処理補助 |
| `screenshot` ^3.0.0 | コラージュを画像化 |
| `image_gallery_saver_plus` ^4.0.1 | 画像を端末アルバムへ保存 |
| `path_provider` / `path` | ローカルファイルパス管理 |

---

## データ永続化

- **散歩軌跡**: `shared_preferences` にキー `walks` で全 `WalkTrack` を JSON 配列として保存（`TrackStorageService`）。同 id は上書き、壊れた要素は無視。
- **写真メタデータ・代表色**: `sqflite` に保存（`color_module.dart` 内のテーブル）。
- **写真本体**: アプリのドキュメントディレクトリ配下にコピー保存。

---

## ビルド・配布

- **CI/CD**: ルートに `codemagic.yaml` 配置済み。Windows 開発機からも iOS ビルドが回せる構成。
- **Dart SDK**: ^3.12.1
- **iOS 側設定**: `ios/Runner/Info.plist` にカメラ・位置情報の利用説明が必要（標準 Flutter 雛形）

---

## 設計上のメモ

- **計算ロジックと描画の分離**: `FogClearingService` や `GhostTrack` は座標計算だけを担当し、`CustomPainter` や `Timer` など副作用は呼び出し側に集約されている。テスタブルさを意識した構成。
- **モデルとサービスの素直な分け方**: `*_pin.dart` / `*_track.dart` がモデル、`*_service.dart` が永続化や外部 IO、`*_screen.dart` / `*_sheet.dart` / `*_marker.dart` が UI、`*_module.dart` が機能ひとまとまり（色抽出、コラージュ）という命名規則。
- **大物**: `collage_module.dart` は 3300 行で 3 種のコラージュ画面を 1 ファイルに同居させているため、今後のリファクタ候補（自動／自由／グリッドで分割可能）。
