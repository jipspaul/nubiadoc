/// Résultat d'une opération d'authentification.
class AuthResult {
  const AuthResult({
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;
}

/// Contrat du dépôt d'authentification.
abstract class AuthRepository {
  Future<AuthResult> login({required String email, required String password});

  Future<AuthResult> register({
    required String email,
    required String password,
    required String cguVersion,
  });
}

/// Implémentation fictive pour POC/démo — données non-PII.
///
/// Simule POST /v1/auth/login et POST /v1/auth/register.
class FakeAuthRepository implements AuthRepository {
  @override
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (password.length < 8) {
      throw Exception('Identifiants invalides');
    }
    return const AuthResult(
      accessToken: 'fake-access-token',
      refreshToken: 'fake-refresh-token',
    );
  }

  @override
  Future<AuthResult> register({
    required String email,
    required String password,
    required String cguVersion,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return const AuthResult(
      accessToken: 'fake-access-token',
      refreshToken: 'fake-refresh-token',
    );
  }
}
