import 'package:equatable/equatable.dart';

sealed class ClinicalSessionEvent extends Equatable {
  const ClinicalSessionEvent();

  @override
  List<Object?> get props => [];
}

/// Démarre la séance — POST /v1/cabinet/appointments/{id}/start.
final class SessionStartRequested extends ClinicalSessionEvent {
  const SessionStartRequested({required this.appointmentId});

  final String appointmentId;

  @override
  List<Object?> get props => [appointmentId];
}

/// Ajoute un acte CCAM — POST /v1/cabinet/consultations/{id}/acts.
final class SessionActAdded extends ClinicalSessionEvent {
  const SessionActAdded({
    required this.consultationId,
    required this.ccamCode,
    required this.label,
    this.tooth,
    this.amountCents,
    this.included = false,
  });

  final String consultationId;
  final String ccamCode;
  final String label;
  final String? tooth;
  final int? amountCents;
  final bool included;

  @override
  List<Object?> get props =>
      [consultationId, ccamCode, label, tooth, amountCents, included];
}

/// Supprime un acte CCAM — DELETE /v1/cabinet/consultations/{id}/acts/{actId}.
final class SessionActRemoved extends ClinicalSessionEvent {
  const SessionActRemoved({
    required this.consultationId,
    required this.actId,
  });

  final String consultationId;
  final String actId;

  @override
  List<Object?> get props => [consultationId, actId];
}

/// Termine & facture — POST /v1/cabinet/consultations/{id}/complete.
final class SessionCompleteRequested extends ClinicalSessionEvent {
  const SessionCompleteRequested({required this.consultationId});

  final String consultationId;

  @override
  List<Object?> get props => [consultationId];
}
