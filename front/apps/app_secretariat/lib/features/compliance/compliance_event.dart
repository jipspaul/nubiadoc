import 'package:equatable/equatable.dart';

sealed class ComplianceEvent extends Equatable {
  const ComplianceEvent();

  @override
  List<Object?> get props => [];
}

/// Charge l'échéancier de conformité du cabinet.
class ComplianceLoadRequested extends ComplianceEvent {
  const ComplianceLoadRequested();
}

/// Ajoute un item à l'échéancier (#7169).
class ComplianceCreateRequested extends ComplianceEvent {
  const ComplianceCreateRequested({
    required this.kind,
    required this.label,
    this.subjectUserId,
    this.equipmentLabel,
    required this.dueDate,
    this.recurrenceMonths,
  });

  final String kind;
  final String label;
  final String? subjectUserId;
  final String? equipmentLabel;

  /// Échéance ISO `YYYY-MM-DD`.
  final String dueDate;
  final int? recurrenceMonths;

  @override
  List<Object?> get props =>
      [kind, label, subjectUserId, equipmentLabel, dueDate, recurrenceMonths];
}

/// Clôture un item en un tap (#7169).
class ComplianceCompleteRequested extends ComplianceEvent {
  const ComplianceCompleteRequested(this.itemId);

  final String itemId;

  @override
  List<Object?> get props => [itemId];
}

/// Rattache un justificatif déjà présent au coffre-fort documentaire.
class ComplianceEvidenceAttachRequested extends ComplianceEvent {
  const ComplianceEvidenceAttachRequested({
    required this.itemId,
    required this.evidenceDocumentId,
  });

  final String itemId;
  final String evidenceDocumentId;

  @override
  List<Object?> get props => [itemId, evidenceDocumentId];
}
