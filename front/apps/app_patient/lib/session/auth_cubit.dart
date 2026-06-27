import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Authentication state shared by the app shell and the router guard.
sealed class AuthState {
  const AuthState();
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.session);
  final AuthSession session;
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated([this.message]);
  final String? message;
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

/// Drives patient login/logout using the shared [LoginUseCase] + [GetMeUseCase].
class AuthCubit extends Cubit<AuthState> with SafeEmitMixin<AuthState> {
  AuthCubit({
    required LoginUseCase login,
    required GetMeUseCase getMe,
    required LogoutUseCase logout,
    required TokenStorage tokenStorage,
    required DeviceRegistrationService deviceRegistration,
  })  : _login = login,
        _getMe = getMe,
        _logout = logout,
        _tokenStorage = tokenStorage,
        _deviceRegistration = deviceRegistration,
        super(const AuthUnknown());

  final LoginUseCase _login;
  final GetMeUseCase _getMe;
  final LogoutUseCase _logout;
  final TokenStorage _tokenStorage;
  final DeviceRegistrationService _deviceRegistration;

  /// Called at startup: restore session from a stored token if present.
  Future<void> restore() async {
    try {
      final token = await _tokenStorage.getAccessToken();
      if (token == null || token.isEmpty) {
        safeEmit(const AuthUnauthenticated());
        return;
      }
      final result = await _getMe();
      result.fold(
        (_) => safeEmit(const AuthUnauthenticated()),
        (account) => safeEmit(AuthAuthenticated(_sessionFrom(account))),
      );
    } catch (_) {
      safeEmit(const AuthUnauthenticated());
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    emit(const AuthLoading());
    try {
      final result = await _login(email: email, password: password);
      result.fold(
        (failure) => safeEmit(AuthUnauthenticated(failure.message)),
        (account) {
          _deviceRegistration.registerOnLogin('patient');
          safeEmit(AuthAuthenticated(_sessionFrom(account)));
        },
      );
    } catch (_) {
      safeEmit(const AuthUnauthenticated('Erreur de connexion.'));
    }
  }

  Future<void> signOut() async {
    await _logout();
    safeEmit(const AuthUnauthenticated());
  }

  AuthSession _sessionFrom(PatientAccount account) => AuthSession(
        kind: UserKind.patient,
        userId: account.id,
        accountId: account.id,
        displayName: account.displayName,
      );
}
