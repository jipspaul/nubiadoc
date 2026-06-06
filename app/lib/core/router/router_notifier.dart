import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nubia_patient/core/storage/token_storage.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_bloc.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_state.dart';

/// Notifies [GoRouter] when auth state changes.
///
/// Listens to [AuthBloc] (or falls back to [TokenStorage] on startup) so
/// that the GoRouter redirect guard re-evaluates when the user logs in or out.
class RouterNotifier extends ChangeNotifier {
  RouterNotifier(this._tokenStorage);

  final TokenStorage _tokenStorage;
  bool _isAuthenticated = false;
  StreamSubscription<AuthState>? _authSubscription;

  bool get isAuthenticated => _isAuthenticated;

  /// Subscribe to [AuthBloc] to keep [isAuthenticated] in sync.
  void addAuthListener(AuthBloc bloc) {
    _authSubscription?.cancel();
    _authSubscription = bloc.stream.listen((state) {
      if (state is AuthAuthenticated) {
        _isAuthenticated = true;
        notifyListeners();
      } else if (state is AuthUnauthenticated) {
        _isAuthenticated = false;
        notifyListeners();
      }
    });
  }

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

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
