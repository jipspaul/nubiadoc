import 'package:equatable/equatable.dart';

/// Un item de l'échéancier de conformité ARS/DMSM (#7170) — formation,
/// contrôle d'équipement, registre, ou autre. Source :
/// `GET /v1/cabinet/compliance-items`.
class ComplianceItem extends Equatable {
  final String id;
  final String kind;
  final String label;
  final String? subjectUserId;
  final String? equipmentLabel;

  /// Échéance, format `YYYY-MM-DD`.
  final String dueDate;
  final int? recurrenceMonths;
  final String status;
  final String? doneAt;
  final String? evidenceDocumentId;

  /// `overdue` | `due_j7` | `due_j30` | `null` (pas d'alerte), calculé côté
  /// back à la lecture sur [dueDate] — jamais persisté.
  final String? alertLevel;
  final String createdAt;

  const ComplianceItem({
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

  bool get isDone => status == 'done';
  bool get hasAlert => alertLevel != null;

  @override
  List<Object?> get props => [id, status, alertLevel];
}
