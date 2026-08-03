import 'package:equatable/equatable.dart';

abstract class ConsultationCliniqueEvent extends Equatable {
  const ConsultationCliniqueEvent();

  @override
  List<Object?> get props => [];
}

class ConsultationCliniqueLoadRequested extends ConsultationCliniqueEvent {
  final String consultationId;
  const ConsultationCliniqueLoadRequested(this.consultationId);

  @override
  List<Object?> get props => [consultationId];
}

class ConsultationCliniqueActAddRequested extends ConsultationCliniqueEvent {
  final String ccamCode;
  final String label;
  final String? tooth;
  final int? amountCents;
  final bool included;

  const ConsultationCliniqueActAddRequested({
    required this.ccamCode,
    required this.label,
    this.tooth,
    this.amountCents,
    this.included = false,
  });

  @override
  List<Object?> get props => [ccamCode, label, tooth, amountCents, included];
}

class ConsultationCliniqueCompleteRequested extends ConsultationCliniqueEvent {
  const ConsultationCliniqueCompleteRequested();
}

class ConsultationCliniqueNoteSaveRequested extends ConsultationCliniqueEvent {
  final String note;
  const ConsultationCliniqueNoteSaveRequested(this.note);

  @override
  List<Object?> get props => [note];
}

class ConsultationHistoriqueRequested extends ConsultationCliniqueEvent {
  const ConsultationHistoriqueRequested();
}

/// Consomme l'erreur d'action transitoire après affichage (snackbar) — #3403.
class ConsultationCliniqueActionErrorConsumed
    extends ConsultationCliniqueEvent {
  const ConsultationCliniqueActionErrorConsumed();
}

/// Dent sélectionnée pour le prochain acte (#4048) — tap sur l'odontogramme
/// intégré ou le bottom-sheet mobile.
class ConsultationCliniqueToothSelected extends ConsultationCliniqueEvent {
  final String tooth;
  const ConsultationCliniqueToothSelected(this.tooth);

  @override
  List<Object?> get props => [tooth];
}

/// Désélectionne la dent courante.
class ConsultationCliniqueToothCleared extends ConsultationCliniqueEvent {
  const ConsultationCliniqueToothCleared();
}

/// Consomme la proposition de mise à jour d'odontogramme après affichage du
/// dialogue (que le praticien ait validé ou ignoré).
class ConsultationCliniqueToothActConsumed extends ConsultationCliniqueEvent {
  const ConsultationCliniqueToothActConsumed();
}

/// Consomme l'alerte clinique bloquante après acquittement du dialogue —
/// #4057/#4058.
class ConsultationCliniqueClinicalRiskWarningConsumed
    extends ConsultationCliniqueEvent {
  const ConsultationCliniqueClinicalRiskWarningConsumed();
}
