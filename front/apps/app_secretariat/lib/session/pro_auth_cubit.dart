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
  const AuthUnauthenticated([this.message, this.invalidInvite = false]);
  final String? message;
  final bool invalidInvite;
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
    required RegisterUseCase register,
    required TokenStorage tokenStorage,
    required DeviceRegistrationService deviceRegistration,
    required String app,
  })  : _login = login,
        _logout = logout,
        _register = register,
        _tokenStorage = tokenStorage,
        _deviceRegistration = deviceRegistration,
        _app = app,
        super(const AuthUnknown());

  final LoginUseCase _login;
  final LogoutUseCase _logout;
  final RegisterUseCase _register;
  final TokenStorage _tokenStorage;
  final DeviceRegistrationService _deviceRegistration;
  final String _app;

  Future<void> restore() async {
    try {
      final token = await _tokenStorage.getAccessToken();
      if (token == null || token.isEmpty) {
        emit(const AuthUnauthenticated());
        return;
      }
      emit(AuthAuthenticated(_session()));
    } catch (_) {
      emit(const AuthUnauthenticated());
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    emit(const AuthLoading());
    try {
      final result = await _login(email: email, password: password);
      result.fold(
        (failure) => emit(AuthUnauthenticated(failure.message)),
        (_) {
          _deviceRegistration.registerOnLogin(_app);
          emit(AuthAuthenticated(_session()));
        },
      );
    } catch (_) {
      emit(const AuthUnauthenticated('Erreur de connexion.'));
    }
  }

  Future<void> registerWithInvitation({
    required String email,
    required String password,
    required String inviteToken,
    required bool acceptCgu,
    String cguVersion = '1.0',
  }) async {
    emit(const AuthLoading());
    try {
      final result = await _register(
        email: email,
        password: password,
        acceptCgu: acceptCgu,
        cguVersion: cguVersion,
        inviteToken: inviteToken,
      );
      result.fold(
        (failure) => emit(AuthUnauthenticated(
          failure.message,
          failure is InvalidInviteFailure,
        )),
        (_) {
          _deviceRegistration.registerOnLogin(_app);
          emit(AuthAuthenticated(_session()));
        },
      );
    } catch (_) {
      emit(const AuthUnauthenticated("Erreur lors de l'inscription."));
    }
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
