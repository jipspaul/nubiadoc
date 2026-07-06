import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'admin_secretariats_event.dart';
import 'admin_secretariats_state.dart';

class AdminSecretiariatsBloc
    extends Bloc<AdminSecretiariatsEvent, AdminSecretiariatsState>
    with SafeEmitMixin<AdminSecretiariatsState> {
  final ListSecretiariatsUseCase _listSecretariats;
  final AddSecretariatUseCase _addSecretariat;

  AdminSecretiariatsBloc({
    required ListSecretiariatsUseCase listSecretariats,
    required AddSecretariatUseCase addSecretariat,
  })  : _listSecretariats = listSecretariats,
        _addSecretariat = addSecretariat,
        super(const AdminSecretiariatsInitial()) {
    on<AdminSecretiariatsLoadRequested>(_onLoad);
    on<AdminSecretiariatsInviteRequested>(_onInvite);
  }

  /// Crée le secrétariat + provisionne son premier membre (le back envoie
  /// le mail d'invitation), puis recharge la liste.
  Future<void> _onInvite(
    AdminSecretiariatsInviteRequested event,
    Emitter<AdminSecretiariatsState> emit,
  ) async {
    try {
      final result = await _addSecretariat(
        name: event.name,
        email: event.email,
      );
      await result.fold(
        (failure) async =>
            safeEmit(AdminSecretiariatsInviteFailed(failure.message)),
        (_) async {
          safeEmit(AdminSecretiariatsInviteSent(event.email));
          await _onLoad(const AdminSecretiariatsLoadRequested(), emit);
        },
      );
    } catch (_) {
      safeEmit(
        const AdminSecretiariatsInviteFailed("Échec de l'invitation."),
      );
    }
  }

  Future<void> _onLoad(
    AdminSecretiariatsLoadRequested event,
    Emitter<AdminSecretiariatsState> emit,
  ) async {
    emit(const AdminSecretiariatsLoading());
    try {
      final result = await _listSecretariats();
      result.fold(
        (failure) => safeEmit(AdminSecretiariatsError(failure.message)),
        (secretariats) => secretariats.isEmpty
            ? safeEmit(const AdminSecretiariatsEmpty())
            : safeEmit(AdminSecretiariatsLoaded(secretariats: secretariats)),
      );
    } catch (_) {
      safeEmit(const AdminSecretiariatsError('Erreur de chargement.'));
    }
  }
}
