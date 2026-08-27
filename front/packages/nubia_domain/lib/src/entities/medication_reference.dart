import 'package:equatable/equatable.dart';

/// Référence produit issue du référentiel médicament (DCI, forme galénique,
/// classe thérapeutique). La classe thérapeutique est purement descriptive
/// (teinte neutre côté UI) : aucune logique de contre-indication/allergie
/// n'en découle côté domaine (ADR-009 §8.6, périmètre MDR exclu).
class MedicationReference extends Equatable {
  /// Identifiant du produit dans le référentiel médicament.
  final String id;

  /// Dénomination Commune Internationale, ex. "Amoxicilline".
  final String dci;

  /// Forme galénique, ex. "comprimé dispersible".
  final String galenicForm;

  /// Classe thérapeutique, ex. "Pénicilline", "Macrolide".
  final String therapeuticClass;

  const MedicationReference({
    required this.id,
    required this.dci,
    required this.galenicForm,
    required this.therapeuticClass,
  });

  @override
  List<Object?> get props => [id, dci, galenicForm, therapeuticClass];
}
