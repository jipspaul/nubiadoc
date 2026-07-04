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

/// Pharmacy auth cubit. Login commun ([LoginUseCase]) puis sélection du
/// contexte tenant : `GET /v1/me` → `pharmacy_memberships`, puis
/// `POST /v1/auth/select-pharmacy-context` qui échange le token de login
/// contre le JWT `kind:"pharma"` (persisté par la couche data).
///
/// Un compte sans appartenance pharmacie est déconnecté avec un message
/// explicite. Multi-pharmacies : la première appartenance est retenue
/// (sélecteur à venir — une seule pharmacie par compte dans le seed démo).
class PharmaAuthCubit extends Cubit<AuthState> {
  PharmaAuthCubit({
    required LoginUseCase login,
    required LogoutUseCase logout,
    required TokenStorage tokenStorage,
    required DeviceRegistrationService deviceRegistration,
    required GetPharmacyMembershipsUseCase memberships,
    required SelectPharmacyContextUseCase selectContext,
    required String app,
  })  : _login = login,
        _logout = logout,
        _tokenStorage = tokenStorage,
        _deviceRegistration = deviceRegistration,
        _memberships = memberships,
        _selectContext = selectContext,
        _app = app,
        super(const AuthUnknown());

  final LoginUseCase _login;
  final LogoutUseCase _logout;
  final TokenStorage _tokenStorage;
  final DeviceRegistrationService _deviceRegistration;
  final GetPharmacyMembershipsUseCase _memberships;
  final SelectPharmacyContextUseCase _selectContext;
  final String _app;

  static const String _noMembershipMessage =
      'Aucun espace pharmacie n’est associé à ce compte.';

  Future<void> restore() async {
    try {
      final token = await _tokenStorage.getAccessToken();
      if (token == null || token.isEmpty) {
        emit(const AuthUnauthenticated());
        return;
      }
      // Le token persisté peut être expiré ou encore kind:"pro" : on rejoue
      // la sélection de contexte (l'interceptor rafraîchit au besoin).
      await _enterPharmacyContext(silent: true);
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
          final entered = await _enterPharmacyContext(silent: false);
          if (entered) {
            _deviceRegistration.registerOnLogin(_app);
          }
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

  /// memberships → select-pharmacy-context → Authenticated.
  /// [silent] : sur un restore, les échecs redeviennent un simple
  /// Unauthenticated sans message d'erreur (session périmée, pas une action
  /// de l'utilisateur). Retourne true si la session est ouverte.
  Future<bool> _enterPharmacyContext({required bool silent}) async {
    final membershipsResult = await _memberships();
    return membershipsResult.fold(
      (failure) async {
        emit(AuthUnauthenticated(silent ? null : failure.message));
        return false;
      },
      (memberships) async {
        if (memberships.isEmpty) {
          await _logout();
          emit(AuthUnauthenticated(silent ? null : _noMembershipMessage));
          return false;
        }
        final contextResult = await _selectContext(
          memberships.first.pharmacyId,
        );
        return contextResult.fold(
          (failure) {
            emit(AuthUnauthenticated(silent ? null : failure.message));
            return false;
          },
          (context) {
            emit(
              AuthAuthenticated(
                AuthSession(
                  kind: UserKind.pro,
                  userId: 'me',
                  role: proRoleFromString(context.role),
                  contextLabel: PharmaConfig.spaceLabel,
                ),
              ),
            );
            return true;
          },
        );
      },
    );
  }
}
