import 'package:nubia_domain/nubia_domain.dart';

sealed class CabinetPayoutsState {
  const CabinetPayoutsState();
}

class CabinetPayoutsLoading extends CabinetPayoutsState {
  const CabinetPayoutsLoading();

  @override
  bool operator ==(Object other) => other is CabinetPayoutsLoading;

  @override
  int get hashCode => runtimeType.hashCode;
}

class CabinetPayoutsLoaded extends CabinetPayoutsState {
  const CabinetPayoutsLoaded(
    this.payouts, {
    this.selectedPayoutId,
    this.selectedMonth,
  });

  final List<CabinetPayout> payouts;

  /// Virement affiché dans le volet de détail — `null` si aucun sélectionné.
  final String? selectedPayoutId;

  /// Mois affiché par le sélecteur d'en-tête (design-v2, point 4b) —
  /// premier jour du mois sur lequel `payouts` est filtré. `null` seulement
  /// dans les tests qui construisent l'état à la main sans l'exercer ; le
  /// bloc fournit toujours une valeur réelle.
  final DateTime? selectedMonth;

  // `CabinetPayout` (Equatable) ne compare que `id` : on vérifie aussi
  // `reconciliationStatus` ici pour que le bloc réémette bien après
  // #5111 (marquer rapproché mute ce champ sur un payout de même id).
  @override
  bool operator ==(Object other) =>
      other is CabinetPayoutsLoaded &&
      other.selectedPayoutId == selectedPayoutId &&
      other.selectedMonth == selectedMonth &&
      other.payouts.length == payouts.length &&
      List.generate(
        payouts.length,
        (i) =>
            other.payouts[i] == payouts[i] &&
            other.payouts[i].reconciliationStatus ==
                payouts[i].reconciliationStatus,
      ).every((b) => b);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(payouts),
        Object.hashAll(payouts.map((p) => p.reconciliationStatus)),
        selectedPayoutId,
        selectedMonth,
      );
}

class CabinetPayoutsError extends CabinetPayoutsState {
  const CabinetPayoutsError(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is CabinetPayoutsError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}
