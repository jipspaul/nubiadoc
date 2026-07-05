import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'admin_membres_event.dart';
import 'admin_membres_state.dart';

class AdminMembresBloc extends Bloc<AdminMembresEvent, AdminMembresState>
    with SafeEmitMixin<AdminMembresState> {
  final ListMembersUseCase _listMembers;
  final ListSecretiariatsUseCase _listSecretariats;
  final InviteMemberUseCase _inviteMember;

  AdminMembresBloc({
    required ListMembersUseCase listMembers,
    required ListSecretiariatsUseCase listSecretariats,
    required InviteMemberUseCase inviteMember,
  })  : _listMembers = listMembers,
        _listSecretariats = listSecretariats,
        _inviteMember = inviteMember,
        super(const AdminMembresInitial()) {
    on<AdminMembresLoadRequested>(_onLoad);
    on<AdminMembresInviteRequested>(_onInvite);
  }

  Future<void> _onLoad(
    AdminMembresLoadRequested event,
    Emitter<AdminMembresState> emit,
  ) async {
    emit(const AdminMembresLoading());
    try {
      final membersResult = await _listMembers();
      final secretariatsResult = await _listSecretariats();

      final failure = membersResult.fold((f) => f, (_) => null) ??
          secretariatsResult.fold((f) => f, (_) => null);

      if (failure != null) {
        safeEmit(AdminMembresError(failure.message));
        return;
      }

      final members = membersResult.getOrElse(() => []);
      final secretariats = secretariatsResult.getOrElse(() => []);

      if (members.isEmpty && secretariats.isEmpty) {
        safeEmit(const AdminMembresEmpty());
      } else {
        safeEmit(
            AdminMembresLoaded(members: members, secretariats: secretariats));
      }
    } catch (_) {
      safeEmit(const AdminMembresError('Erreur de chargement.'));
    }
  }

  Future<void> _onInvite(
    AdminMembresInviteRequested event,
    Emitter<AdminMembresState> emit,
  ) async {
    emit(const AdminMembresLoading());
    try {
      final result = await _inviteMember(event.email, event.role);
      result.fold(
        (failure) => safeEmit(AdminMembresError(failure.message)),
        (_) {
          safeEmit(const AdminMembresInviteSuccess());
          add(const AdminMembresLoadRequested());
        },
      );
    } catch (_) {
      safeEmit(const AdminMembresError("Erreur lors de l'invitation."));
    }
  }
}
