import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../infirmiere_config.dart';

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

/// Auth de l'app infirmière : réutilise le [LoginUseCase] partagé, amorce une
/// [AuthSession] stub (`role:nurse`).
///
/// TODO(nubia): après login, appeler `GET /v1/me` puis
/// `POST /v1/auth/select-nurse-context` pour obtenir un token `kind:nurse`
/// (les endpoints `/v1/nurse/*` l'exigent). Le backend expose déjà les deux.
class InfirmiereAuthCubit extends Cubit<AuthState> {
  InfirmiereAuthCubit({
    required LoginUseCase login,
    required LogoutUseCase logout,
    required TokenStorage tokenStorage,
    required DeviceRegistrationService deviceRegistration,
  })  : _login = login,
        _logout = logout,
        _tokenStorage = tokenStorage,
        _deviceRegistration = deviceRegistration,
        super(const AuthUnknown());

  final LoginUseCase _login;
  final LogoutUseCase _logout;
  final TokenStorage _tokenStorage;
  final DeviceRegistrationService _deviceRegistration;

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
          _deviceRegistration.registerOnLogin('infirmiere');
          emit(AuthAuthenticated(_session()));
        },
      );
    } catch (_) {
      emit(const AuthUnauthenticated('Erreur de connexion.'));
    }
  }

  Future<void> signOut() async {
    await _logout();
    emit(const AuthUnauthenticated());
  }

  AuthSession _session() => const AuthSession(
        kind: UserKind.pro,
        userId: 'me',
        role: InfirmiereConfig.role,
      );
}
