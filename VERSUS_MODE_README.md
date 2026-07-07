# 対戦モード（versus）実装メモ

散歩マップアプリに「対戦モード」を追加した際の、セットアップ手順・
Firestore ルール・設計上の判断をまとめる。

## 1. 追加・変更ファイル

新規:
- `lib/models/polygon.dart` … 多角形ドメインモデル `WalkPolygon`
- `lib/models/friend_profile.dart` … `FriendProfile`
- `lib/services/firebase_auth_service.dart`
- `lib/services/firestore_sync_service.dart`
- `lib/services/storage_upload_service.dart`
- `lib/services/polygon_overlap_service.dart` … 凸包 / 交差 / 面積 / 実効面積
- `lib/services/area_ranking_service.dart`
- `lib/services/polygon_storage_service.dart` … 自分の多角形のローカル永続化
- `lib/versus_mode_overlay.dart`
- `lib/polygon_choice_sheet.dart`（機能3：新規 / 既存追加）
- `lib/color_picker_sheet.dart`（機能3：色選択）
- `lib/friends_screen.dart`
- `lib/area_ranking_screen.dart`

変更:
- `lib/map_mode.dart`（`versus` 追加）
- `lib/mode_switcher.dart`（4 タブ化、Icons.sports_kabaddi / 赤系）
- `lib/photo_pin.dart`（`ownerUid` / `polygonId` を null 許容で追加・JSON 後方互換）
- `lib/photo_service.dart`（破棄用 `deletePhotoFile` 追加）
- `lib/map_screen.dart`（対戦分岐・撮影フロー差し替え・購読・FAB）
- `lib/main.dart`（`Firebase.initializeApp()`）
- `pubspec.yaml`（firebase_core / firebase_auth / cloud_firestore / firebase_storage）

## 2. Firebase 初期化手順

1. `dart pub global activate flutterfire_cli`（未導入なら）
2. プロジェクト直下で `flutterfire configure` を実行し、
   対象プラットフォームを選択 → `lib/firebase_options.dart` が生成される。
3. `lib/main.dart` のコメントを解除し、
   `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` に変更。
4. Android: 生成された `android/app/google-services.json` を配置
   （`flutterfire configure` が自動配置）。`android/build.gradle` と
   `android/app/build.gradle` に Google Services プラグインが入っているか確認。
5. iOS: `ios/Runner/GoogleService-Info.plist` を配置。
6. Firebase コンソールで Authentication →「匿名」を有効化。
   Firestore（ネイティブモード）と Storage を作成。
7. `flutter pub get` → ビルド。

※ `firebase_options.dart` 未生成でもアプリは起動する（main で例外を握り潰し、
   対戦モードのみ無効になる）。通常/再生/霧モードは Firebase なしで従来通り動作。

## 3. Firestore セキュリティルール（例）

```js
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // ユーザ本体: 自分のみ書き込み可。読み取りは認証済みなら可（コード検索のため）。
    match /users/{uid} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == uid;

      // フレンドサブコレクション: 本人のみ読み書き可
      match /friends/{friendUid} {
        allow read, write: if request.auth != null && request.auth.uid == uid;
      }
    }

    // 多角形（機能2 v4）:
    //   領域奪取では A の所有者が B（他人）の多角形を「分裂 → 元B削除 +
    //   B1..Bn を ownerUid=B で新規作成」する必要がある。そのため
    //   create / update / delete を「認証済みなら誰でも可」に緩めている。
    //   ゲーム性のためのトレードオフ。読み取りは認証済みなら可。
    match /polygons/{polygonId} {
      allow read: if request.auth != null;
      allow create, update, delete: if request.auth != null;
    }

    // 写真メタ（機能2 v4）:
    //   分裂時に A が B の写真の polygonId 付け替え / 削除を行うため、
    //   同様に認証済みなら書き込み可とする。
    match /photos/{photoId} {
      allow read: if request.auth != null;
      allow create, update, delete: if request.auth != null;
    }
  }
}
```

Storage ルール（例）:

```js
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /photos/{ownerUid}/{fileName} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == ownerUid;
    }
  }
}
```

## 4. 設計上の判断・トレードオフ

- **クラス名 `WalkPolygon`**: flutter_map が `Polygon` をエクスポートしており衝突するため、
  ドメインモデルは `WalkPolygon` とした（仕様の "Polygon" に対応）。
- **フレンド限定はクライアント側フィルタ**: 仕様通り、`polygons` は認証済みなら全件読み取り可とし、
  描画/集計時に「自分＋フレンド」へ絞る（`watchAllPolygons` を購読）。データ量が増える場合は
  `whereIn` での所有者絞り込みやページングへ移行する余地がある。
- **機能2の上書きは描画順＋面積控除の二段構え**: 視覚的には createdAt 昇順で重ね描き（新しい多角形が上）。
  ランキングの実効面積は `area(B) − Σ area(B∩A_newer)` を計算し、複数の新しい多角形による
  二重控除は B の面積で上限クランプする簡易実装（仕様で許容）。上書きは **versus モードのみ**。
- **確定タイミング**: 同色の準備中グループにピンを貯め、3 枚目で confirmed=true・createdAt 確定→
  Firestore へ upload。2 枚目まではピンのみ（塗り・共有なし）。
- **色不一致時は写真を破棄**: 機能3で「ピンを立てない」と判断した場合、撮影済みファイルを
  `PhotoService.deletePhotoFile` で即削除（Storage にも上げない）。
- **撮影フローは normal/versus 共通**: 仕様通り両モードで「新規/既存追加」フローを使う。
  Firestore への同期は versus 参加中のみ（normal 専用ユーザはローカル保存に留まる）。
- **後方互換**: PhotoPin の新フィールドは null 許容＆JSON では null 時にキーを省略するため、
  既存の `photo_pins.json` をそのまま読み込める。面積は緯度補正つき正距円筒近似（簡易）。
