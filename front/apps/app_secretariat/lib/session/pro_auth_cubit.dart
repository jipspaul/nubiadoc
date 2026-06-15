import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../pro_config.dart';

sealed class AuthState {
  const AuthState();
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.session);
  final AuthSession session;
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated([this.message]);
  final String? message;
}

/// Professional auth cubit. Reuses the shared [LoginUseCase]; the role is
/// fixed per app for the skeleton (see [ProConfig.role]).
///
/// TODO(nubia): parse `GET /v1/me` to derive role/cabinet from the JWT instead
/// of assuming [ProConfig.role], and reject mismatched roles at login.
class ProAuthCubit extends Cubit<AuthState> {
  ProAuthCubit({
    required LoginUseCase login,
    required LogoutUseCase logout,
    required TokenStorage tokenStorage,
  })  : _login = login,
        _logout = logout,
        _tokenStorage = tokenStorage,
        super(const AuthUnknown());

  final LoginUseCase _login;
  final LogoutUseCase _logout;
  final TokenStorage _tokenStorage;

  Future<void> restore() async {
    final token = await _tokenStorage.getAccessToken();
    if (token == null || token.isEmpty) {
      emit(const AuthUnauthenticated());
      return;
    }
    emit(AuthAuthenticated(_session()));
  }

  Future<void> signIn({required String email, required String password}) async {
    emit(const AuthLoading());
    final result = await _login(email: email, password: password);
    result.fold(
      (failure) => emit(AuthUnauthenticated(failure.message)),
      (_) => emit(AuthAuthenticated(_session())),
    );
  }

  Future<void> signOut() async {
    await _logout();
    emit(const AuthUnauthenticated());
  }

  AuthSession _session() => const AuthSession(
        kind: UserKind.pro,
        userId: 'me',
        role: ProConfig.role,
      );
}
