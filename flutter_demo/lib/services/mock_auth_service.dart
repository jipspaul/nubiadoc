/// Service d'authentification mock pour le POC/démo.
///
/// 1 utilisateur fictif hardcodé : demo@nubia.fr / Demo1234!
/// Zéro PII — données de démonstration uniquement.
class MockAuthService {
  static const _mockEmail = 'demo@nubia.fr';
  static const _mockPassword = 'Demo1234!';

  /// Retourne `true` si les identifiants correspondent à l'utilisateur mock.
  bool validateCredentials({required String email, required String password}) {
    return email.trim() == _mockEmail && password == _mockPassword;
  }
}
