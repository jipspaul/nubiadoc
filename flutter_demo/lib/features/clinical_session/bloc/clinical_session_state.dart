import 'package:equatable/equatable.dart';

import '../models/clinical_session.dart';

sealed class ClinicalSessionState extends Equatable {
  const ClinicalSessionState();

  @override
  List<Object?> get props => [];
}

final class ClinicalSessionInitial extends ClinicalSessionState {
  const ClinicalSessionInitial();
}

final class ClinicalSessionLoading extends ClinicalSessionState {
  const ClinicalSessionLoading();
}

/// Séance en cours (ou nouvellement démarrée).
final class ClinicalSessionActive extends ClinicalSessionState {
  const ClinicalSessionActive(this.session);

  final ClinicalSession session;

  @override
  List<Object?> get props => [session];
}

/// Opération en cours sur les actes (ajout/suppression).
final class ClinicalSessionActBusy extends ClinicalSessionState {
  const ClinicalSessionActBusy(this.session);

  final ClinicalSession session;

  @override
  List<Object?> get props => [session];
}

/// Séance terminée et facturée.
final class ClinicalSessionCompleted extends ClinicalSessionState {
  const ClinicalSessionCompleted(this.session);

  final ClinicalSession session;

  @override
  List<Object?> get props => [session];
}

final class ClinicalSessionError extends ClinicalSessionState {
  const ClinicalSessionError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
