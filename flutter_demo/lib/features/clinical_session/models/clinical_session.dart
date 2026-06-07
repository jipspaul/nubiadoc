import 'package:equatable/equatable.dart';

import 'ccam_act.dart';

/// Statut d'une séance clinique.
enum SessionStatus {
  /// RDV confirmé, séance pas encore démarrée.
  confirmed,

  /// Séance en cours (POST …/start a été appelé).
  inProgress,

  /// Séance terminée et facturée (POST …/complete a été appelé).
  completed,
}

/// Contexte clinique d'une séance — GET /v1/cabinet/consultations/{id}.
class ClinicalSession extends Equatable {
  const ClinicalSession({
    required this.id,
    required this.appointmentId,
    required this.patientName,
    required this.status,
    required this.acts,
  });

  final String id;
  final String appointmentId;
  final String patientName;
  final SessionStatus status;
  final List<CcamAct> acts;

  ClinicalSession copyWith({
    SessionStatus? status,
    List<CcamAct>? acts,
  }) {
    return ClinicalSession(
      id: id,
      appointmentId: appointmentId,
      patientName: patientName,
      status: status ?? this.status,
      acts: acts ?? this.acts,
    );
  }

  @override
  List<Object?> get props => [id, appointmentId, patientName, status, acts];
}
