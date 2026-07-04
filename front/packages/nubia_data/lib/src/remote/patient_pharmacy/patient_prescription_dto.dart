import 'package:nubia_domain/src/entities/patient_prescription.dart';
import 'package:nubia_domain/src/entities/prescription.dart';

class PatientPrescriptionDto {
  final String id;
  final String status;
  final String? documentId;
  final String createdAt;
  final String? signedAt;

  const PatientPrescriptionDto({
    required this.id,
    required this.status,
    this.documentId,
    required this.createdAt,
    this.signedAt,
  });

  factory PatientPrescriptionDto.fromJson(Map<String, dynamic> json) =>
      PatientPrescriptionDto(
        id: json['id'] as String,
        status: json['status'] as String? ?? 'draft',
        documentId: json['document_id'] as String?,
        createdAt: json['created_at'] as String? ??
            DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
        signedAt: json['signed_at'] as String?,
      );

  PatientPrescription toDomain() => PatientPrescription(
        id: id,
        status: switch (status) {
          'signed' => PrescriptionStatus.signed,
          'sent' => PrescriptionStatus.sent,
          _ => PrescriptionStatus.draft,
        },
        documentId: documentId,
        createdAt: DateTime.parse(createdAt),
        signedAt: signedAt != null ? DateTime.parse(signedAt!) : null,
      );
}
