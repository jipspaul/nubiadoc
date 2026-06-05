import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';

/// Stores JWT access + refresh tokens in the device keychain.
@singleton
class TokenStorage {
  static const _accessKey = 'nubia_access_token';
  static const _refreshKey = 'nubia_refresh_token';

  final FlutterSecureStorage _storage;
  const TokenStorage(this._storage);

  Future<String?> getAccessToken() => _storage.read(key: _accessKey);
  Future<String?> getRefreshToken() => _storage.read(key: _refreshKey);

  Future<void> saveTokens({required String access, required String refresh}) async {
    await Future.wait([
      _storage.write(key: _accessKey, value: access),
      _storage.write(key: _refreshKey, value: refresh),
    ]);
  }

  Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: _accessKey),
      _storage.delete(key: _refreshKey),
    ]);
  }
}
