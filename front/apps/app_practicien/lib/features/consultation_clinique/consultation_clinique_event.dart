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
  /// Statut serveur à filtrer (`in_progress`/`completed`/`cancelled`), ou
  /// `null` pour la page par défaut (non filtrée) — #7033 : le filtre de
  /// l'historique doit interroger le serveur plutôt que trier la seule page
  /// déjà chargée en mémoire.
  final String? status;
  const ConsultationHistoriqueRequested({this.status});

  @override
  List<Object?> get props => [status];
}

/// Consomme l'erreur d'action transitoire après affichage (snackbar) — #3403.
class ConsultationCliniqueActionErrorConsumed
    extends ConsultationCliniqueEvent {
  const ConsultationCliniqueActionErrorConsumed();
}

/// Le praticien a acquitté l'alerte clinique (bouton « Compris ») — rejoue
/// l'ajout de l'acte en attente avec `riskAcknowledged: true` (#7911) :
/// avant ce fix, « Compris » ne faisait que fermer le dialogue sans jamais
/// permettre d'enregistrer l'acte pratiqué.
class ConsultationCliniqueClinicalRiskAcknowledged
    extends ConsultationCliniqueEvent {
  const ConsultationCliniqueClinicalRiskAcknowledged();
}
