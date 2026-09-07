import 'package:dio/dio.dart';
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
  /// Dernier `nurse_id` sélectionné — permet de re-scoper le token après un
  /// refresh (le refresh renvoie un token de login `kind:"pro"`, qui serait
  /// rejeté en 403 par /v1/nurse/*). Voir [reselectContext].
  String? _selectedNurseId;

  InfirmiereAuthCubit({
    required LoginUseCase login,
    required LogoutUseCase logout,
    required TokenStorage tokenStorage,
    required DeviceRegistrationService deviceRegistration,
    required ApiClient api,
  })  : _login = login,
        _logout = logout,
        _tokenStorage = tokenStorage,
        _deviceRegistration = deviceRegistration,
        _api = api,
        super(const AuthUnknown());

  final LoginUseCase _login;
  final LogoutUseCase _logout;
  final TokenStorage _tokenStorage;
  final DeviceRegistrationService _deviceRegistration;
  final ApiClient _api;

  /// Après le login (token `kind:pro`), échange contre un token `kind:nurse` :
  /// GET /v1/nurse/memberships → POST /v1/auth/select-nurse-context {nurse_id}.
  /// Sans ce token, les endpoints /v1/nurse/* renvoient 403.
  Future<void> _applyNurseContext() async {
    try {
      final mem = await _api.dio.get<List<dynamic>>('/nurse/memberships');
      final list = mem.data ?? const [];
      if (list.isEmpty) return; // pas de tenant infirmier → reste kind:pro
      final nurseId = (list.first as Map)['nurse_id'];
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/auth/select-nurse-context',
        data: {'nurse_id': nurseId},
      );
      final token = res.data?['access_token'] as String?;
      if (token == null) return;
      final refresh = await _tokenStorage.getRefreshToken() ?? '';
      await _tokenStorage.saveTokens(access: token, refresh: refresh);
      _selectedNurseId = nurseId as String?;
    } catch (_) {
      // Non bloquant : l'utilisateur reste connecté (kind:pro) même si le
      // select-context échoue ; l'UI signalera les 403 sur /nurse/*.
    }
  }

  /// Re-scope le token courant sur le contexte infirmier après un refresh.
  ///
  /// Branché sur `AuthInterceptor.onTokensRefreshed` (cf. hook côté app
  /// pharmacie) : le refresh réécrit un token de login `kind:"pro"` en
  /// storage ; on l'échange contre un JWT `kind:"nurse"` via le [plainDio]
  /// fourni (sans interceptors — pas de réentrance sur le refresh en cours).
  /// No-op tant qu'aucun contexte n'a été sélectionné.
  Future<void> reselectContext(Dio plainDio) async {
    final nurseId = _selectedNurseId;
    if (nurseId == null) return;
    final access = await _tokenStorage.getAccessToken();
    if (access == null || access.isEmpty) return;
    final response = await plainDio.post<Map<String, dynamic>>(
      '/auth/select-nurse-context',
      data: {'nurse_id': nurseId},
      options: Options(headers: {'Authorization': 'Bearer $access'}),
    );
    final token = response.data?['access_token'] as String?;
    if (token == null || token.isEmpty) return;
    final refresh = await _tokenStorage.getRefreshToken();
    await _tokenStorage.saveTokens(access: token, refresh: refresh ?? '');
  }

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
      await result.fold(
        (failure) async => emit(AuthUnauthenticated(failure.message)),
        (_) async {
          _deviceRegistration.registerOnLogin('infirmiere');
          await _applyNurseContext(); // échange le token pro → nurse
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
