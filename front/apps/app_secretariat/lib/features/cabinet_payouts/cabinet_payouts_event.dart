import 'package:equatable/equatable.dart';

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

/// Change le mois affiché par le sélecteur d'en-tête (design-v2, point 4b)
/// — le rapprochement est un travail mensuel : recharge et filtre la liste
/// sur ce nouveau mois.
class CabinetPayoutsMonthChanged extends CabinetPayoutsEvent
    with EquatableMixin {
  const CabinetPayoutsMonthChanged(this.month);

  /// N'importe quel jour du mois ciblé — seuls l'année et le mois comptent.
  final DateTime month;

  @override
  List<Object?> get props => [month];
}
