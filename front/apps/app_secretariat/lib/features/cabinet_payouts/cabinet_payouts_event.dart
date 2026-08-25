abstract class CabinetPayoutsEvent {
  const CabinetPayoutsEvent();
}

class CabinetPayoutsLoadRequested extends CabinetPayoutsEvent {
  const CabinetPayoutsLoadRequested();
}

/// Sélectionne (ou désélectionne si déjà sélectionné) un virement pour
/// affichage du volet de détail.
class CabinetPayoutSelected extends CabinetPayoutsEvent {
  const CabinetPayoutSelected(this.id);

  final String id;
}

/// Marque le virement comme rapproché (décision humaine, jamais automatique).
class CabinetPayoutMarkedReconciled extends CabinetPayoutsEvent {
  const CabinetPayoutMarkedReconciled(this.id);

  final String id;
}

/// Signale l'écart au comptable (feedback utilisateur seulement, aucun état
/// métier dédié côté virement).
class CabinetPayoutFlaggedToAccountant extends CabinetPayoutsEvent {
  const CabinetPayoutFlaggedToAccountant(this.id);

  final String id;
}
