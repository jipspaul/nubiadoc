import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class AdminMembresState extends Equatable {
  const AdminMembresState();

  @override
  List<Object?> get props => [];
}

final class AdminMembresInitial extends AdminMembresState {
  const AdminMembresInitial();
}

final class AdminMembresLoading extends AdminMembresState {
  const AdminMembresLoading();
}

final class AdminMembresEmpty extends AdminMembresState {
  const AdminMembresEmpty();
}

final class AdminMembresLoaded extends AdminMembresState {
  const AdminMembresLoaded({required this.members, required this.secretariats});

  final List<Member> members;
  final List<Secretariat> secretariats;

  @override
  List<Object?> get props => [members, secretariats];
}

final class AdminMembresError extends AdminMembresState {
  const AdminMembresError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Accès refusé (403) : l'utilisateur n'est pas administrateur du cabinet.
/// État informatif distinct de l'erreur générique — il masque toute action
/// d'écriture (invitation), qui échouerait de toute façon en 403.
final class AdminMembresForbidden extends AdminMembresState {
  const AdminMembresForbidden(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

final class AdminMembresInviteSuccess extends AdminMembresState {
  const AdminMembresInviteSuccess();
}
