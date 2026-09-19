import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class LetterComposeState extends Equatable {
  const LetterComposeState();

  @override
  List<Object?> get props => [];
}

class LetterComposeLoading extends LetterComposeState {
  const LetterComposeLoading();
}

/// Chargement des modèles de courrier en échec — sans modèle, l'écran ne
/// peut rien composer, contrairement au patient (affichage passif en cas
/// d'échec, cf. [LetterComposeReady.patient]).
class LetterComposeError extends LetterComposeState {
  const LetterComposeError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class LetterComposeReady extends LetterComposeState {
  const LetterComposeReady({
    required this.templates,
    this.patient,
    this.submitting = false,
    this.error,
  });

  final List<LetterTemplate> templates;

  /// `null` tant que `GetCabinetPatientUseCase` n'a pas répondu (ou en cas
  /// d'échec) — l'en-tête retombe alors sur un nom générique.
  final CabinetPatient? patient;
  final bool submitting;

  /// Erreur de la dernière tentative de génération (formulaire toujours
  /// monté, saisie conservée) — `null` une fois une nouvelle tentative lancée.
  final String? error;

  @override
  List<Object?> get props => [templates, patient, submitting, error];
}

/// Courrier généré et ajouté aux documents du patient (`POST .../letters`).
class LetterComposeGenerated extends LetterComposeState {
  const LetterComposeGenerated(this.letter);

  final GeneratedLetter letter;

  @override
  List<Object?> get props => [letter];
}
