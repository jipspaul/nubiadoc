import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'admin_secretariats_event.dart';
import 'admin_secretariats_state.dart';

class AdminSecretariatsBloc
    extends Bloc<AdminSecretariatsEvent, AdminSecretariatsState>
    with SafeEmitMixin<AdminSecretariatsState> {
  final ListSecretariatsUseCase _listSecretariats;
  final AddSecretariatUseCase _addSecretariat;

  AdminSecretariatsBloc({
    required ListSecretariatsUseCase listSecretariats,
    required AddSecretariatUseCase addSecretariat,
  })  : _listSecretariats = listSecretariats,
        _addSecretariat = addSecretariat,
        super(const AdminSecretariatsInitial()) {
    on<AdminSecretariatsLoadRequested>(_onLoad);
    on<AdminSecretariatsInviteRequested>(_onInvite);
  }

  /// Crée le secrétariat + provisionne son premier membre (le back envoie
  /// le mail d'invitation), puis recharge la liste.
  Future<void> _onInvite(
    AdminSecretariatsInviteRequested event,
    Emitter<AdminSecretariatsState> emit,
  ) async {
    try {
      final result = await _addSecretariat(
        name: event.name,
        email: event.email,
      );
      await result.fold(
        (failure) async =>
            safeEmit(AdminSecretariatsInviteFailed(failure.message)),
        (_) async {
          safeEmit(AdminSecretariatsInviteSent(event.email));
          await _onLoad(const AdminSecretariatsLoadRequested(), emit);
        },
      );
    } catch (_) {
      safeEmit(
        const AdminSecretariatsInviteFailed("Échec de l'invitation."),
      );
    }
  }

  Future<void> _onLoad(
    AdminSecretariatsLoadRequested event,
    Emitter<AdminSecretariatsState> emit,
  ) async {
    emit(const AdminSecretariatsLoading());
    try {
      final result = await _listSecretariats();
      result.fold(
        (failure) => safeEmit(AdminSecretariatsError(failure.message)),
        (secretariats) => secretariats.isEmpty
            ? safeEmit(const AdminSecretariatsEmpty())
            : safeEmit(AdminSecretariatsLoaded(secretariats: secretariats)),
      );
    } catch (_) {
      safeEmit(const AdminSecretariatsError('Erreur de chargement.'));
    }
  }
}
