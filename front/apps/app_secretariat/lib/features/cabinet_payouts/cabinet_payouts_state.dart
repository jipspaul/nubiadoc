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
    this.actionResult,
  });

  final List<CabinetPayout> payouts;

  /// Virement affiché dans le volet de détail — `null` si aucun sélectionné.
  final String? selectedPayoutId;

  /// Mois affiché par le sélecteur d'en-tête (design-v2, point 4b) —
  /// premier jour du mois sur lequel `payouts` est filtré. `null` seulement
  /// dans les tests qui construisent l'état à la main sans l'exercer ; le
  /// bloc fournit toujours une valeur réelle.
  final DateTime? selectedMonth;

  /// Retour ponctuel de la dernière action déclenchée (signaler au
  /// comptable) — `null` hors de tout retour à afficher (#6945 : porte le
  /// feedback UI fidèle à la réponse serveur, plutôt qu'un snackbar de
  /// succès affiché indépendamment de la requête réseau).
  final CabinetPayoutActionResult? actionResult;

  // `CabinetPayout` (Equatable) ne compare que `id` : on vérifie aussi
  // `reconciliationStatus`/`flaggedToAccountant` ici pour que le bloc
  // réémette bien après #5111 (marquer rapproché) et #6945 (signaler au
  // comptable), qui mutent ces champs sur un payout de même id.
  // `actionResult` compare par identité (pas d'override d'égalité) : une
  // nouvelle instance à chaque action force la réémission même si le
  // message est identique au précédent.
  @override
  bool operator ==(Object other) =>
      other is CabinetPayoutsLoaded &&
      other.selectedPayoutId == selectedPayoutId &&
      other.selectedMonth == selectedMonth &&
      other.actionResult == actionResult &&
      other.payouts.length == payouts.length &&
      List.generate(
        payouts.length,
        (i) =>
            other.payouts[i] == payouts[i] &&
            other.payouts[i].reconciliationStatus ==
                payouts[i].reconciliationStatus &&
            other.payouts[i].flaggedToAccountant ==
                payouts[i].flaggedToAccountant,
      ).every((b) => b);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(payouts),
        Object.hashAll(payouts.map((p) => p.reconciliationStatus)),
        Object.hashAll(payouts.map((p) => p.flaggedToAccountant)),
        selectedPayoutId,
        selectedMonth,
        actionResult,
      );
}

/// Retour ponctuel d'une action déclenchée sur un virement (#6945) — porté
/// par `CabinetPayoutsLoaded` le temps d'un affichage (snackbar), plutôt
/// qu'affiché de façon synchrone et inconditionnelle par le bouton comme
/// avant ce correctif.
class CabinetPayoutActionResult {
  CabinetPayoutActionResult.success(this.message) : isSuccess = true;

  CabinetPayoutActionResult.failure(this.message) : isSuccess = false;

  final String message;
  final bool isSuccess;
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
