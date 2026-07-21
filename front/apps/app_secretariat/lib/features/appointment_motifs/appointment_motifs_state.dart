import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class AppointmentMotifsState extends Equatable {
  const AppointmentMotifsState();

  @override
  List<Object?> get props => [];
}

final class AppointmentMotifsInitial extends AppointmentMotifsState {
  const AppointmentMotifsInitial();
}

final class AppointmentMotifsLoading extends AppointmentMotifsState {
  const AppointmentMotifsLoading();
}

final class AppointmentMotifsEmpty extends AppointmentMotifsState {
  const AppointmentMotifsEmpty();
}

final class AppointmentMotifsLoaded extends AppointmentMotifsState {
  const AppointmentMotifsLoaded(this.motifs);

  final List<AppointmentMotif> motifs;

  @override
  List<Object?> get props => [motifs];
}

final class AppointmentMotifsError extends AppointmentMotifsState {
  const AppointmentMotifsError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Écriture (création/modif/suppression) refusée par le backend (403) —
/// admin-only, cf. #4085. Distinct de l'erreur générique pour un message
/// explicite ; la liste elle-même (GET) n'est jamais 403 pour un rôle pro.
final class AppointmentMotifsWriteForbidden extends AppointmentMotifsState {
  const AppointmentMotifsWriteForbidden(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

final class AppointmentMotifsMutationSuccess extends AppointmentMotifsState {
  const AppointmentMotifsMutationSuccess();
}
