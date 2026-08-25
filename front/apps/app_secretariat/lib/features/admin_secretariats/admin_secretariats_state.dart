import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class AdminSecretariatsState extends Equatable {
  const AdminSecretariatsState();

  @override
  List<Object?> get props => [];
}

final class AdminSecretariatsInitial extends AdminSecretariatsState {
  const AdminSecretariatsInitial();
}

final class AdminSecretariatsLoading extends AdminSecretariatsState {
  const AdminSecretariatsLoading();
}

final class AdminSecretariatsEmpty extends AdminSecretariatsState {
  const AdminSecretariatsEmpty();
}

final class AdminSecretariatsLoaded extends AdminSecretariatsState {
  const AdminSecretariatsLoaded({required this.secretariats});

  final List<Secretariat> secretariats;

  @override
  List<Object?> get props => [secretariats];
}

/// Invitation envoyée — état transitoire consommé par la page (snackbar)
/// avant le rechargement de la liste.
final class AdminSecretariatsInviteSent extends AdminSecretariatsState {
  const AdminSecretariatsInviteSent(this.email);

  final String email;

  @override
  List<Object?> get props => [email];
}

/// Échec d'invitation — la liste courante reste affichée derrière.
final class AdminSecretariatsInviteFailed extends AdminSecretariatsState {
  const AdminSecretariatsInviteFailed(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

final class AdminSecretariatsError extends AdminSecretariatsState {
  const AdminSecretariatsError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
