/// フレンド（または自分自身）のプロフィール
class FriendProfile {
  final String uid;
  final String displayName;

  /// 表示用の短縮フレンドコード（任意）
  final String? code;

  const FriendProfile({
    required this.uid,
    required this.displayName,
    this.code,
  });

  factory FriendProfile.fromMap(String uid, Map<String, dynamic> map) {
    return FriendProfile(
      uid: uid,
      displayName: map['displayName'] as String? ?? '名無し',
      code: map['code'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'displayName': displayName,
    if (code != null) 'code': code,
  };
}
