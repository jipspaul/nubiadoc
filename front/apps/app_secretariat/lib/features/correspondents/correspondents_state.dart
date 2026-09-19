import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class CorrespondentsState extends Equatable {
  const CorrespondentsState();

  @override
  List<Object?> get props => [];
}

final class CorrespondentsInitial extends CorrespondentsState {
  const CorrespondentsInitial();
}

final class CorrespondentsLoading extends CorrespondentsState {
  const CorrespondentsLoading();
}

final class CorrespondentsEmpty extends CorrespondentsState {
  const CorrespondentsEmpty();
}

final class CorrespondentsLoaded extends CorrespondentsState {
  const CorrespondentsLoaded(this.correspondents);

  final List<CabinetCorrespondent> correspondents;

  @override
  List<Object?> get props => [correspondents];
}

final class CorrespondentsError extends CorrespondentsState {
  const CorrespondentsError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

final class CorrespondentsMutationSuccess extends CorrespondentsState {
  const CorrespondentsMutationSuccess();
}

/// Écriture (création/modif/suppression) refusée par le backend — cas
/// « supprimé alors qu'il est référencé » (409, `AppError::CorrespondentInUse`)
/// ou validation. Distinct de la liste (`CorrespondentsError`) pour un
/// message explicite sans perdre l'affichage courant.
final class CorrespondentsMutationError extends CorrespondentsState {
  const CorrespondentsMutationError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
