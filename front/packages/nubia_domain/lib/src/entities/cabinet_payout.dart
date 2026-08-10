import 'package:equatable/equatable.dart';

enum PayoutProvider { stripe, gocardless }

enum PayoutReconciliationStatus { reconciled, toVerify }

/// Un virement Stripe/GoCardless rapproché des paiements internes du
/// cabinet (#4129). Source : `GET /v1/cabinet/payouts` — données MOCK côté
/// back (pas de compte Stripe Connect/GoCardless configuré), au format des
/// API Payouts réelles des deux providers.
class CabinetPayout extends Equatable {
  final String id;
  final PayoutProvider provider;
  final int amountCents;
  final String currency;
  final DateTime arrivalDate;
  final PayoutReconciliationStatus reconciliationStatus;
  final int internalPaymentsTotalCents;

  const CabinetPayout({
    required this.id,
    required this.provider,
    required this.amountCents,
    required this.currency,
    required this.arrivalDate,
    required this.reconciliationStatus,
    required this.internalPaymentsTotalCents,
  });

  /// Écart entre le montant du payout et la somme des paiements internes
  /// trouvés pour la même journée — affiché par l'UI quand non rapproché.
  int get differenceCents => amountCents - internalPaymentsTotalCents;

  @override
  List<Object?> get props => [id];
}
