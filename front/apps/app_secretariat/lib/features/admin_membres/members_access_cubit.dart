import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Résultat du sondage d'accès à l'administration des membres.
enum MembersAccess { unknown, granted, denied }

/// Rôle-gate de l'entrée de navigation « Membres ».
///
/// L'app secrétariat fixe [ProConfig.role] à `secretary` pour toutes les
/// sessions : le JWT ne distingue pas le secrétaire-admin du secrétaire simple.
/// Avant #7351, le seul signal disponible était le **403** renvoyé par
/// `GET /v1/cabinet/members` (réservée à `admin`). #7351 a ouvert cette
/// lecture à tout rôle pro (secretary/practitioner/admin) pour alimenter le
/// sélecteur « Assigné à » des tâches — la route ne renvoie donc plus jamais
/// 403 pour un secrétaire simple, et ce signal est mort (#7925). Le rôle réel
/// de l'appelant reste cependant dans la réponse : chaque membre listé porte
/// son propre `role`, y compris l'appelant lui-même. On retrouve sa propre
/// entrée via [userId] (= `AuthSession.userId`, issu de `GET /v1/me`) et on
/// masque l'entrée « Membres » quand ce rôle n'est pas `admin` — même
/// contrainte que les écritures (`POST/PATCH/DELETE /v1/cabinet/members`,
/// `POST /v1/cabinet/invite-links`), toutes restées `ProAdminClaims`.
class MembersAccessCubit extends Cubit<MembersAccess> {
  MembersAccessCubit(this._listMembers) : super(MembersAccess.unknown);

  final ListMembersUseCase _listMembers;

  Future<void> probe(String userId) async {
    final result = await _listMembers();
    result.fold(
      (failure) {
        // Un 403 reste possible pour un token mal formé/obsolète : traité
        // comme non-admin. Toute autre erreur (réseau, 5xx…) laisse l'entrée
        // visible pour ne pas verrouiller un admin légitime.
        if (failure is ServerFailure && failure.statusCode == 403) {
          emit(MembersAccess.denied);
        }
      },
      (members) {
        final self = members.where((m) => m.id == userId);
        // Appelant absent de la liste (ne devrait pas arriver, il est membre
        // de son propre cabinet) : on ne verrouille pas sur une ambiguïté.
        if (self.isEmpty) {
          emit(MembersAccess.granted);
        } else {
          emit(self.first.role == MemberRole.admin
              ? MembersAccess.granted
              : MembersAccess.denied);
        }
      },
    );
  }

  /// L'entrée « Membres » n'est masquée que lorsqu'un 403 a confirmé le
  /// non-admin. Par défaut (inconnu, accordé ou erreur non-403) elle reste
  /// visible : on ne laisse pas d'onglet mort dès que le rôle est connu, sans
  /// pour autant verrouiller un admin sur une erreur transitoire.
  bool get canManageMembers => state != MembersAccess.denied;
}
