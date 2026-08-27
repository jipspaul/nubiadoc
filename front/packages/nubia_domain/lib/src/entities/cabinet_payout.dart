import 'package:equatable/equatable.dart';

enum PayoutProvider { stripe, gocardless }

enum PayoutReconciliationStatus { reconciled, toVerify }

/// Une ligne de paiement interne enregistrée le jour du virement (#5110) —
/// permet au volet d'expliquer un écart (« piste probable ») plutôt que de
/// juste le signaler, sans jamais rapprocher automatiquement quoi que ce
/// soit. Aussi affichée telle quelle dans la liste « Paiements internes du
/// jour » (#5109).
class InternalPayment extends Equatable {
  final String patientName;
  final String time;
  final int amountCents;
  final String methodLabel;
  final bool reconcilableByProvider;

  const InternalPayment({
    required this.patientName,
    required this.time,
    required this.amountCents,
    required this.methodLabel,
    required this.reconcilableByProvider,
  });

  @override
  List<Object?> get props =>
      [patientName, time, amountCents, methodLabel, reconcilableByProvider];
}

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
  final List<InternalPayment> internalPayments;

  const CabinetPayout({
    required this.id,
    required this.provider,
    required this.amountCents,
    required this.currency,
    required this.arrivalDate,
    required this.reconciliationStatus,
    required this.internalPaymentsTotalCents,
    this.internalPayments = const [],
  });

  /// Écart entre le montant du payout et la somme des paiements internes
  /// trouvés pour la même journée — affiché par l'UI quand non rapproché.
  int get differenceCents => amountCents - internalPaymentsTotalCents;

  @override
  List<Object?> get props => [id];
}
