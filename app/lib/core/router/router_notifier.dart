import 'package:flutter/foundation.dart';
import 'package:nubia_patient/core/storage/token_storage.dart';

/// Notifies [GoRouter] when auth state changes.
///
/// Listens to [TokenStorage] and exposes [isAuthenticated] so the
/// GoRouter redirect guard can decide whether to allow or block a route.
class RouterNotifier extends ChangeNotifier {
  RouterNotifier(this._tokenStorage);

  final TokenStorage _tokenStorage;
  bool _isAuthenticated = false;

  bool get isAuthenticated => _isAuthenticated;

  /// Call once at startup (and after every login/logout) to refresh the
  /// auth state and trigger a GoRouter re-evaluation.
  Future<void> refreshAuth() async {
    final token = await _tokenStorage.getAccessToken();
    final wasAuthenticated = _isAuthenticated;
    _isAuthenticated = token != null && token.isNotEmpty;
    if (_isAuthenticated != wasAuthenticated) {
      notifyListeners();
    }
  }

  void markAuthenticated() {
    _isAuthenticated = true;
    notifyListeners();
  }

  void markUnauthenticated() {
    _isAuthenticated = false;
    notifyListeners();
  }
}
