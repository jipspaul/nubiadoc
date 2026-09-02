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

/// Drives patient login/logout using the shared [LoginUseCase] + [GetAccountUseCase].
class AuthCubit extends Cubit<AuthState> with SafeEmitMixin<AuthState> {
  AuthCubit({
    required LoginUseCase login,
    required GetAccountUseCase getAccount,
    required LogoutUseCase logout,
    required TokenStorage tokenStorage,
    required DeviceRegistrationService deviceRegistration,
  })  : _login = login,
        _getAccount = getAccount,
        _logout = logout,
        _tokenStorage = tokenStorage,
        _deviceRegistration = deviceRegistration,
        super(const AuthUnknown());

  final LoginUseCase _login;
  final GetAccountUseCase _getAccount;
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
      final result = await _getAccount();
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
      await result.fold(
        (failure) async => safeEmit(AuthUnauthenticated(failure.message)),
        (account) async {
          _deviceRegistration.registerOnLogin('patient');
          // /auth/login ne renvoie pas le nom du compte : on le récupère via
          // /account (pas /me, qui ne renvoie jamais first_name/last_name —
          // cf. #6178) pour que la session ait un displayName correct dès le
          // login (sans ça, patientDisplayName reste vide jusqu'au prochain
          // restore() au redémarrage de l'app).
          final me = await _getAccount();
          safeEmit(
            AuthAuthenticated(_sessionFrom(me.fold((_) => account, (a) => a))),
          );
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
