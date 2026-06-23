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
  bool _resolved = false;

  bool get isAuthenticated => _isAuthenticated;

  /// Whether the initial auth state has been determined (token store read or an
  /// explicit mark*). The splash route waits on this before redirecting, so the
  /// app doesn't flash the login screen during boot.
  bool get isResolved => _resolved;

  /// Re-reads the token store and notifies if the auth state flipped.
  Future<void> refreshAuth() async {
    final token = await _tokenStorage.getAccessToken();
    final wasAuthenticated = _isAuthenticated;
    final wasResolved = _resolved;
    _isAuthenticated = token != null && token.isNotEmpty;
    _resolved = true;
    if (_isAuthenticated != wasAuthenticated || !wasResolved) notifyListeners();
  }

  void markAuthenticated() {
    final changed = !_isAuthenticated || !_resolved;
    _isAuthenticated = true;
    _resolved = true;
    if (changed) notifyListeners();
  }

  void markUnauthenticated() {
    final changed = _isAuthenticated || !_resolved;
    _isAuthenticated = false;
    _resolved = true;
    if (changed) notifyListeners();
  }
}
