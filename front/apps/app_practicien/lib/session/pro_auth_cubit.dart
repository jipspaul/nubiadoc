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
    required DeviceRegistrationService deviceRegistration,
    required ApiClient api,
    required String app,
  })  : _login = login,
        _logout = logout,
        _tokenStorage = tokenStorage,
        _deviceRegistration = deviceRegistration,
        _api = api,
        _app = app,
        super(const AuthUnknown());

  final LoginUseCase _login;
  final LogoutUseCase _logout;
  final TokenStorage _tokenStorage;
  final DeviceRegistrationService _deviceRegistration;
  final ApiClient _api;
  final String _app;

  Future<void> restore() async {
    try {
      final token = await _tokenStorage.getAccessToken();
      if (token == null || token.isEmpty) {
        emit(const AuthUnauthenticated());
        return;
      }
      emit(AuthAuthenticated(await _session()));
    } catch (_) {
      emit(const AuthUnauthenticated());
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    emit(const AuthLoading());
    try {
      final result = await _login(email: email, password: password);
      await result.fold(
        (failure) async => emit(AuthUnauthenticated(failure.message)),
        (_) async {
          _deviceRegistration.registerOnLogin(_app);
          emit(AuthAuthenticated(await _session()));
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

  /// Identité réelle du shell pro (#6170) : `display_name` et le nom du
  /// cabinet courant viennent de `GET /v1/me`, jamais du JWT (qui ne porte
  /// que `sub`/`kind`). Best-effort — un `/me` en échec ne bloque jamais la
  /// session, il retombe silencieusement sur les libellés génériques
  /// existants ([ProConfig.role]/[ProConfig.appTitle]).
  Future<AuthSession> _session() async {
    String userId = 'me';
    String? displayName;
    String? cabinetName;
    try {
      final response = await _api.dio.get<Map<String, dynamic>>('/me');
      userId = response.data?['user_id'] as String? ?? userId;
      displayName = response.data?['display_name'] as String?;
      final memberships = (response.data?['memberships'] as List<dynamic>? ??
              const [])
          .cast<Map<String, dynamic>>();
      final ownRoleMatches = memberships.where(
        (m) => proRoleFromString(m['role'] as String?) == ProConfig.role,
      );
      final match = ownRoleMatches.isNotEmpty
          ? ownRoleMatches.first
          : (memberships.isNotEmpty ? memberships.first : null);
      cabinetName = match?['cabinet_name'] as String?;
    } catch (_) {
      // Non bloquant : voir doc ci-dessus.
    }
    return AuthSession(
      kind: UserKind.pro,
      userId: userId,
      role: ProConfig.role,
      displayName: displayName,
      contextLabel: cabinetName,
    );
  }
}
