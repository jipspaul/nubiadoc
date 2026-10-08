import 'package:equatable/equatable.dart';

import 'prescription.dart';

/// Ordonnance vue depuis le compte patient (id nécessaire pour l'envoi
/// en pharmacie — GET /v1/account/prescriptions).
class PatientPrescription extends Equatable {
  final String id;
  final PrescriptionStatus status;
  final String? documentId;
  final DateTime createdAt;
  final DateTime? signedAt;

  /// Prescripteur (Dr) et cabinet — de quoi distinguer deux ordonnances de
  /// la même journée dans une liste (#6822) ; `null` si non résolu côté API
  /// (profil non listé, ou cabinet hors visibilité patient).
  final String? prescriberName;
  final String? prescriberPractice;

  /// Nombre de lignes de l'ordonnance (#6822).
  final int lineCount;

  const PatientPrescription({
    required this.id,
    required this.status,
    this.documentId,
    required this.createdAt,
    this.signedAt,
    this.prescriberName,
    this.prescriberPractice,
    this.lineCount = 0,
  });

  /// Une ordonnance signée (PDF généré) peut partir en pharmacie ;
  /// `sent` reste re-commandable après annulation.
  bool get canBeSentToPharmacy =>
      documentId != null &&
      (status == PrescriptionStatus.signed ||
          status == PrescriptionStatus.sent);

  @override
  List<Object?> get props => [id, status];
}
