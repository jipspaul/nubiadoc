/// Abstraction du stockage sécurisé du token d'accès.
///
/// L'implémentation prod utilisera flutter_secure_storage.
/// Pour le POC, [InMemoryTokenStorage] garde le token en mémoire.
abstract class TokenStorage {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

/// Implémentation en mémoire pour tests et POC.
class InMemoryTokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> delete() async => _token = null;
}
