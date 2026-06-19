import 'package:flutter/foundation.dart';

import '../storage/token_storage.dart';

/// Drives [GoRouter] re-evaluation when authentication state changes.
///
/// App-agnostic: it knows nothing about any specific bloc. Apps update it by
/// calling [markAuthenticated] / [markUnauthenticated] (e.g. from a listener on
/// their own AuthBloc) or [refreshAuth] at startup.
class RouterNotifier extends ChangeNotifier {
  RouterNotifier(this._tokenStorage);

  final TokenStorage _tokenStorage;
  bool _isAuthenticated = false;

  bool get isAuthenticated => _isAuthenticated;

  /// Re-reads the token store and notifies if the auth state flipped.
  Future<void> refreshAuth() async {
    final token = await _tokenStorage.getAccessToken();
    final wasAuthenticated = _isAuthenticated;
    _isAuthenticated = token != null && token.isNotEmpty;
    if (_isAuthenticated != wasAuthenticated) notifyListeners();
  }

  void markAuthenticated() {
    if (_isAuthenticated) return;
    _isAuthenticated = true;
    notifyListeners();
  }

  void markUnauthenticated() {
    if (!_isAuthenticated) return;
    _isAuthenticated = false;
    notifyListeners();
  }
}
