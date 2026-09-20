import 'package:nubia_domain/src/entities/compliance_item.dart';

class ComplianceItemDto {
  final String id;
  final String kind;
  final String label;
  final String? subjectUserId;
  final String? equipmentLabel;
  final String dueDate;
  final int? recurrenceMonths;
  final String status;
  final String? doneAt;
  final String? evidenceDocumentId;
  final String? alertLevel;
  final String createdAt;

  const ComplianceItemDto({
    required this.id,
    required this.kind,
    required this.label,
    this.subjectUserId,
    this.equipmentLabel,
    required this.dueDate,
    this.recurrenceMonths,
    required this.status,
    this.doneAt,
    this.evidenceDocumentId,
    this.alertLevel,
    required this.createdAt,
  });

  factory ComplianceItemDto.fromJson(Map<String, dynamic> json) =>
      ComplianceItemDto(
        id: json['id'] as String,
        kind: json['kind'] as String,
        label: json['label'] as String,
        subjectUserId: json['subject_user_id'] as String?,
        equipmentLabel: json['equipment_label'] as String?,
        dueDate: json['due_date'] as String,
        recurrenceMonths: json['recurrence_months'] as int?,
        status: json['status'] as String,
        doneAt: json['done_at'] as String?,
        evidenceDocumentId: json['evidence_document_id'] as String?,
        alertLevel: json['alert_level'] as String?,
        createdAt: json['created_at'] as String,
      );

  ComplianceItem toDomain() => ComplianceItem(
        id: id,
        kind: kind,
        label: label,
        subjectUserId: subjectUserId,
        equipmentLabel: equipmentLabel,
        dueDate: dueDate,
        recurrenceMonths: recurrenceMonths,
        status: status,
        doneAt: doneAt,
        evidenceDocumentId: evidenceDocumentId,
        alertLevel: alertLevel,
        createdAt: createdAt,
      );
}
