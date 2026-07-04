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

  const PatientPrescription({
    required this.id,
    required this.status,
    this.documentId,
    required this.createdAt,
    this.signedAt,
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
