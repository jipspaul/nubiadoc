import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class AdminSecretiariatsState extends Equatable {
  const AdminSecretiariatsState();

  @override
  List<Object?> get props => [];
}

final class AdminSecretiariatsInitial extends AdminSecretiariatsState {
  const AdminSecretiariatsInitial();
}

final class AdminSecretiariatsLoading extends AdminSecretiariatsState {
  const AdminSecretiariatsLoading();
}

final class AdminSecretiariatsEmpty extends AdminSecretiariatsState {
  const AdminSecretiariatsEmpty();
}

final class AdminSecretiariatsLoaded extends AdminSecretiariatsState {
  const AdminSecretiariatsLoaded({required this.secretariats});

  final List<Secretariat> secretariats;

  @override
  List<Object?> get props => [secretariats];
}

/// Invitation envoyée — état transitoire consommé par la page (snackbar)
/// avant le rechargement de la liste.
final class AdminSecretiariatsInviteSent extends AdminSecretiariatsState {
  const AdminSecretiariatsInviteSent(this.email);

  final String email;

  @override
  List<Object?> get props => [email];
}

/// Échec d'invitation — la liste courante reste affichée derrière.
final class AdminSecretiariatsInviteFailed extends AdminSecretiariatsState {
  const AdminSecretiariatsInviteFailed(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

final class AdminSecretiariatsError extends AdminSecretiariatsState {
  const AdminSecretiariatsError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
