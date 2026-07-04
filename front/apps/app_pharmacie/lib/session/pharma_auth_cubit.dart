import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../pharma_config.dart';

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

/// Pharmacy auth cubit. Reuses the shared [LoginUseCase] (login commun) ;
/// le rôle est fixé par app pour le squelette (voir [PharmaConfig.role]).
///
/// TODO(nubia): après login, lire `pharmacy_memberships` de `GET /v1/me` puis
/// appeler `POST /v1/auth/select-pharmacy-context` pour obtenir le JWT
/// `kind:"pharma"` (multi-pharmacies : proposer un sélecteur).
class PharmaAuthCubit extends Cubit<AuthState> {
  PharmaAuthCubit({
    required LoginUseCase login,
    required LogoutUseCase logout,
    required TokenStorage tokenStorage,
    required DeviceRegistrationService deviceRegistration,
    required String app,
  })  : _login = login,
        _logout = logout,
        _tokenStorage = tokenStorage,
        _deviceRegistration = deviceRegistration,
        _app = app,
        super(const AuthUnknown());

  final LoginUseCase _login;
  final LogoutUseCase _logout;
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

  Future<void> signOut() async {
    await _logout();
    emit(const AuthUnauthenticated());
  }

  AuthSession _session() => const AuthSession(
        kind: UserKind.pro,
        userId: 'me',
        role: PharmaConfig.role,
        contextLabel: PharmaConfig.spaceLabel,
      );
}
