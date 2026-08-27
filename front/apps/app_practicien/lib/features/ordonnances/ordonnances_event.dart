import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class OrdonnancesEvent extends Equatable {
  const OrdonnancesEvent();

  @override
  List<Object?> get props => [];
}

class OrdonnancesCreateRequested extends OrdonnancesEvent {
  final String patientId;
  final List<PrescriptionItem> items;

  const OrdonnancesCreateRequested({
    required this.patientId,
    required this.items,
  });

  @override
  List<Object?> get props => [patientId, items];
}

class OrdonnancesSignRequested extends OrdonnancesEvent {
  final String prescriptionId;

  const OrdonnancesSignRequested(this.prescriptionId);

  @override
  List<Object?> get props => [prescriptionId];
}

/// Applique un modèle (#4074) : préremplit un brouillon avec les lignes du
/// modèle `templateId` via `POST /v1/cabinet/prescriptions/{id}/apply-template`.
///
/// Émis soit depuis `_DraftReview` avec [prescriptionId] (brouillon déjà
/// créé), soit depuis l'écran de composition avec [patientId] (#4988,
/// modèle choisi avant toute création) : aucun brouillon n'existe encore, le
/// bloc l'orchestre implicitement (apply-template exige un `prescription.id`
/// côté serveur). Un seul des deux est fourni.
class OrdonnancesApplyTemplateRequested extends OrdonnancesEvent {
  final String? prescriptionId;
  final String? patientId;
  final String templateId;

  const OrdonnancesApplyTemplateRequested({
    this.prescriptionId,
    this.patientId,
    required this.templateId,
  }) : assert(prescriptionId != null || patientId != null);

  @override
  List<Object?> get props => [prescriptionId, patientId, templateId];
}

/// Charge l'historique des ordonnances du patient (#4132) — déclenché à
/// l'ouverture de la page quand un `patientId` est fourni.
class OrdonnancesListRequested extends OrdonnancesEvent {
  final String patientId;

  const OrdonnancesListRequested(this.patientId);

  @override
  List<Object?> get props => [patientId];
}

/// Renouvelle une ordonnance passée (#4132) : duplique ses lignes dans un
/// nouveau brouillon via `POST /v1/cabinet/prescriptions/{id}/renew`, puis
/// affiche ce brouillon pour relecture/signature (même écran qu'après
/// création — `OrdonnancesCreated`).
class OrdonnancesRenewRequested extends OrdonnancesEvent {
  final String prescriptionId;

  const OrdonnancesRenewRequested(this.prescriptionId);

  @override
  List<Object?> get props => [prescriptionId];
}
