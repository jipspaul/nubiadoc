import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'kv_store.dart';

KvStore createKvStore() => const _SecureKvStore();

/// Keychain/Keystore sécurisé sur mobile & desktop.
class _SecureKvStore implements KvStore {
  const _SecureKvStore();

  static const _s = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _s.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _s.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _s.delete(key: key);
}
