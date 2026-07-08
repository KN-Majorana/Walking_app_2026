import 'package:firebase_auth/firebase_auth.dart';

/// Firebase 認証（匿名）を扱うサービス。
///
/// 表示名は Firebase Auth 側にも反映するが、アプリ内の正本は
/// Firestore users/{uid}.displayName 側とする（[FirestoreSyncService] が管理）。
class FirebaseAuthService {
  FirebaseAuthService._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static User? get currentUser => _auth.currentUser;
  static String? get uid => _auth.currentUser?.uid;

  /// 未ログインなら匿名サインインし、UID を返す。
  static Future<String> ensureSignedIn() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
    return _auth.currentUser!.uid;
  }

  /// Firebase Auth プロフィールの表示名を更新する。
  static Future<void> updateDisplayName(String name) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.updateDisplayName(name);
  }

  static Stream<User?> authStateChanges() => _auth.authStateChanges();
}
