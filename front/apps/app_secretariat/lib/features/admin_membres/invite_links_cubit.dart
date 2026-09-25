import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// État du générateur de liens d'invitation par rôle (#7148/#7147) — un
/// admin peut générer, pour un rôle donné, un lien à usage multiple copiable
/// et partageable, sans passer par l'invitation nominative par e-mail
/// ([AdminMembresBloc.inviteMember]).
class InviteLinksState extends Equatable {
  const InviteLinksState({
    this.pendingRole,
    this.lastLink,
    this.error,
  });

  /// Rôle dont la génération est en cours (masque le bouton correspondant).
  final MemberRole? pendingRole;
  final CabinetInviteLink? lastLink;
  final String? error;

  InviteLinksState copyWith({
    MemberRole? pendingRole,
    bool clearPendingRole = false,
    CabinetInviteLink? lastLink,
    String? error,
    bool clearError = false,
  }) =>
      InviteLinksState(
        pendingRole:
            clearPendingRole ? null : (pendingRole ?? this.pendingRole),
        lastLink: lastLink ?? this.lastLink,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  List<Object?> get props => [pendingRole, lastLink, error];
}

class InviteLinksCubit extends Cubit<InviteLinksState> {
  InviteLinksCubit(this._createInviteLink) : super(const InviteLinksState());

  final CreateInviteLinkUseCase _createInviteLink;

  Future<CabinetInviteLink?> generate(MemberRole role) async {
    emit(state.copyWith(pendingRole: role, clearError: true));
    final result = await _createInviteLink(role);
    return result.fold(
      (failure) {
        emit(state.copyWith(clearPendingRole: true, error: failure.message));
        return null;
      },
      (link) {
        emit(state.copyWith(clearPendingRole: true, lastLink: link));
        return link;
      },
    );
  }
}
