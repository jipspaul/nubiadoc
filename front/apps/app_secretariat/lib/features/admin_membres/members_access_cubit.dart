import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Résultat du sondage d'accès à l'administration des membres.
enum MembersAccess { unknown, granted, denied }

/// Rôle-gate de l'entrée de navigation « Membres ».
///
/// L'app secrétariat fixe [ProConfig.role] à `secretary` pour toutes les
/// sessions : le JWT ne distingue pas le secrétaire-admin du secrétaire simple.
/// Le seul signal fiable du rôle admin est le **403** renvoyé par
/// `GET /v1/cabinet/members` (le back garde correctement la route). On sonde
/// l'endpoint une fois au démarrage et on masque l'entrée « Membres »
/// uniquement lorsqu'un 403 confirme le non-admin — même signal de rôle que le
/// FAB d'invitation (#3426, `AdminMembresForbidden`).
class MembersAccessCubit extends Cubit<MembersAccess> {
  MembersAccessCubit(this._listMembers) : super(MembersAccess.unknown);

  final ListMembersUseCase _listMembers;

  Future<void> probe() async {
    final result = await _listMembers();
    result.fold(
      (failure) {
        // Seul un 403 prouve le non-admin ; toute autre erreur (réseau, 5xx…)
        // laisse l'entrée visible pour ne pas verrouiller un admin légitime.
        if (failure is ServerFailure && failure.statusCode == 403) {
          emit(MembersAccess.denied);
        }
      },
      (_) => emit(MembersAccess.granted),
    );
  }

  /// L'entrée « Membres » n'est masquée que lorsqu'un 403 a confirmé le
  /// non-admin. Par défaut (inconnu, accordé ou erreur non-403) elle reste
  /// visible : on ne laisse pas d'onglet mort dès que le rôle est connu, sans
  /// pour autant verrouiller un admin sur une erreur transitoire.
  bool get canManageMembers => state != MembersAccess.denied;
}
