import 'package:nubia_domain/src/entities/patient_prescription.dart';
import 'package:nubia_domain/src/entities/prescription.dart';

class PatientPrescriptionDto {
  final String id;
  final String status;
  final String? documentId;
  final String createdAt;
  final String? signedAt;
  final String? prescriberName;
  final String? prescriberPractice;
  final int lineCount;

  const PatientPrescriptionDto({
    required this.id,
    required this.status,
    this.documentId,
    required this.createdAt,
    this.signedAt,
    this.prescriberName,
    this.prescriberPractice,
    this.lineCount = 0,
  });

  factory PatientPrescriptionDto.fromJson(Map<String, dynamic> json) =>
      PatientPrescriptionDto(
        id: json['id'] as String,
        status: json['status'] as String? ?? 'draft',
        documentId: json['document_id'] as String?,
        createdAt: json['created_at'] as String? ??
            DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
        signedAt: json['signed_at'] as String?,
        prescriberName: json['prescriber_name'] as String?,
        prescriberPractice: json['prescriber_practice'] as String?,
        lineCount: json['line_count'] as int? ?? 0,
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
        prescriberName: prescriberName,
        prescriberPractice: prescriberPractice,
        lineCount: lineCount,
      );
}
