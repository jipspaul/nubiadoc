import 'package:equatable/equatable.dart';

/// A CCAM act added during a clinical consultation.
class ClinicalAct extends Equatable {
  final String id;
  final String ccamCode;
  final String label;
  final String? tooth;
  final int? amountCents;
  final bool included;

  const ClinicalAct({
    required this.id,
    required this.ccamCode,
    required this.label,
    this.tooth,
    this.amountCents,
    this.included = false,
  });

  @override
  List<Object?> get props => [id, ccamCode, label, tooth, amountCents, included];
}

/// The clinical session context returned by GET /v1/cabinet/consultations/{id}.
class ClinicalSession extends Equatable {
  final String id;
  final String appointmentId;
  final String status; // 'in_progress' | 'completed'
  final List<ClinicalAct> acts;

  const ClinicalSession({
    required this.id,
    required this.appointmentId,
    required this.status,
    required this.acts,
  });

  bool get isCompleted => status == 'completed';

  @override
  List<Object?> get props => [id, appointmentId, status, acts];
}

/// Result of POST .../complete
class SessionCompleteResult extends Equatable {
  final String? invoiceId;
  final String? nextStep;

  const SessionCompleteResult({this.invoiceId, this.nextStep});

  @override
  List<Object?> get props => [invoiceId, nextStep];
}
