# ローディング画面の背景

このフォルダに `loading_source.png` を置くと、起動時のローディング画面
（`lib/loading_screen.dart` の `LoadingGate`）の背景として全画面に表示される。

- ファイル名: `loading_source.png`（変えたい場合は `LoadingGate.backgroundAsset` も直す）
- 推奨サイズ: 1170 x 2532 以上の縦長。`BoxFit.cover` で表示されるため、
  端末の比率差で上下左右が少し切れる前提で、中央に余裕をもたせた構図がよい
- 画像が無い場合は緑のグラデーション（`_LoadingView._fallbackGradient`）で代替表示される

このフォルダは `pubspec.yaml` の `assets:` に登録されている。
フォルダごと消すとビルドが通らなくなるので、空にする場合もこの README は残すこと。
