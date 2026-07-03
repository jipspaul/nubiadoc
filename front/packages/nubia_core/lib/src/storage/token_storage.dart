import 'kv_store.dart';

/// Stores JWT access + refresh tokens and FCM device token.
///
/// Backed by [KvStore] : keychain sécurisé sur mobile/desktop, localStorage sur
/// le web (persistance fiable au rechargement).
class TokenStorage {
  static const _accessKey = 'nubia_access_token';
  static const _refreshKey = 'nubia_refresh_token';
  static const _fcmKey = 'nubia_fcm_token';

  final KvStore _store;
  const TokenStorage(this._store);

  Future<String?> getAccessToken() => _store.read(_accessKey);
  Future<String?> getRefreshToken() => _store.read(_refreshKey);
  Future<String?> getFcmToken() => _store.read(_fcmKey);

  Future<void> saveTokens(
      {required String access, required String refresh}) async {
    await Future.wait([
      _store.write(_accessKey, access),
      _store.write(_refreshKey, refresh),
    ]);
  }

  Future<void> saveFcmToken(String token) => _store.write(_fcmKey, token);

  Future<void> clearTokens() async {
    await Future.wait([
      _store.delete(_accessKey),
      _store.delete(_refreshKey),
    ]);
  }

  Future<void> clearFcmToken() => _store.delete(_fcmKey);
}
