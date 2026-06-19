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
class AuthCubit extends Cubit<AuthState> {
  AuthCubit({
    required LoginUseCase login,
    required GetMeUseCase getMe,
    required LogoutUseCase logout,
    required TokenStorage tokenStorage,
  })  : _login = login,
        _getMe = getMe,
        _logout = logout,
        _tokenStorage = tokenStorage,
        super(const AuthUnknown());

  final LoginUseCase _login;
  final GetMeUseCase _getMe;
  final LogoutUseCase _logout;
  final TokenStorage _tokenStorage;

  /// Called at startup: restore session from a stored token if present.
  Future<void> restore() async {
    final token = await _tokenStorage.getAccessToken();
    if (token == null || token.isEmpty) {
      emit(const AuthUnauthenticated());
      return;
    }
    final result = await _getMe();
    result.fold(
      (_) => emit(const AuthUnauthenticated()),
      (account) => emit(AuthAuthenticated(_sessionFrom(account))),
    );
  }

  Future<void> signIn({required String email, required String password}) async {
    emit(const AuthLoading());
    final result = await _login(email: email, password: password);
    result.fold(
      (failure) => emit(AuthUnauthenticated(failure.message)),
      (account) => emit(AuthAuthenticated(_sessionFrom(account))),
    );
  }

  Future<void> signOut() async {
    await _logout();
    emit(const AuthUnauthenticated());
  }

  AuthSession _sessionFrom(PatientAccount account) => AuthSession(
        kind: UserKind.patient,
        userId: account.id,
        accountId: account.id,
        displayName: account.displayName,
      );
}
