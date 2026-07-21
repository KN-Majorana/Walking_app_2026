import 'package:path_provider/path_provider.dart';

/// アプリのドキュメントディレクトリを同期的に参照するためのヘルパー。
///
/// ── なぜ必要か ──
/// iOS / Android のアプリコンテナのパスは **不変ではない**。
/// 特に iOS では再インストールやアプリ更新のたびにコンテナ UUID が変わるため、
///   /var/mobile/Containers/Data/Application/<UUID>/Documents/photos/xxx.jpg
/// のような **絶対パスを JSON に保存すると、次回起動時に必ず解決できなくなる**
/// （＝写真が「消えた」ように見える）。
///
/// そこで永続化する値は Documents 配下の **相対パス**（例: `photos/xxx.jpg`）に
/// 統一し、読み出し時にその時点の Documents ディレクトリと結合して絶対パスへ
/// 戻す。[toStorable] / [toAbsolute] がその変換を担う。
///
/// toJson / fromJson は同期メソッドなので、起動時に [init] でパスを
/// キャッシュしておく必要がある（main() から呼ぶ）。
class AppPaths {
  AppPaths._();

  static String? _documentsPath;

  /// キャッシュ済みの Documents ディレクトリのパス。未初期化なら null。
  static String? get documentsPath => _documentsPath;

  /// 起動時に一度だけ呼ぶ。二重呼び出しは無害。
  static Future<void> init() async {
    if (_documentsPath != null) return;
    try {
      _documentsPath = (await getApplicationDocumentsDirectory()).path;
    } catch (_) {
      // 取得できない環境（テスト等）では変換をパススルーにフォールバックする。
    }
  }

  /// 未初期化なら初期化してからパスを返す。
  /// ストレージ系サービスの入口から呼び、init 漏れによる事故を防ぐ。
  static Future<String?> ensureInitialized() async {
    await init();
    return _documentsPath;
  }

  /// 保存用の値へ変換する。
  /// Documents 配下の絶対パスなら相対パスへ、それ以外はそのまま返す。
  static String toStorable(String path) {
    if (path.isEmpty) return path;
    final root = _documentsPath;
    if (root == null || root.isEmpty) return path;
    if (path.startsWith('$root/')) {
      return path.substring(root.length + 1);
    }
    return path;
  }

  /// 読み出し用の値へ変換する。
  /// 相対パスなら現在の Documents ディレクトリと結合する。
  /// 絶対パス（旧データ）はまずそのまま扱い、コンテナ移動で壊れている場合に
  /// 限り Documents 以下の同じ相対位置へ読み替える（旧データ救済）。
  static String toAbsolute(String stored) {
    if (stored.isEmpty) return stored;
    final root = _documentsPath;
    if (root == null || root.isEmpty) return stored;

    // 相対パス（新形式）
    if (!stored.startsWith('/')) {
      return '$root/$stored';
    }

    // 既に現在のコンテナを指しているならそのまま
    if (stored.startsWith('$root/')) return stored;

    // 旧データ救済: 過去のコンテナの絶対パス → 現在の Documents 配下へ読み替え。
    const marker = '/Documents/';
    final idx = stored.indexOf(marker);
    if (idx >= 0) {
      final relative = stored.substring(idx + marker.length);
      return '$root/$relative';
    }
    return stored;
  }
}
