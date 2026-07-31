import 'package:nubia_domain/src/entities/cabinet_payout.dart';

class CabinetPayoutDto {
  final String id;
  final String provider;
  final int amountCents;
  final String currency;
  final String arrivalDate;
  final String reconciliationStatus;
  final int internalPaymentsTotalCents;

  const CabinetPayoutDto({
    required this.id,
    required this.provider,
    required this.amountCents,
    required this.currency,
    required this.arrivalDate,
    required this.reconciliationStatus,
    required this.internalPaymentsTotalCents,
  });

  factory CabinetPayoutDto.fromJson(Map<String, dynamic> json) =>
      CabinetPayoutDto(
        id: json['id'] as String,
        provider: json['provider'] as String,
        amountCents: json['amount_cents'] as int,
        currency: json['currency'] as String,
        arrivalDate: json['arrival_date'] as String,
        reconciliationStatus: json['reconciliation_status'] as String,
        internalPaymentsTotalCents:
            json['internal_payments_total_cents'] as int,
      );

  CabinetPayout toDomain() => CabinetPayout(
        id: id,
        provider: provider == 'gocardless'
            ? PayoutProvider.gocardless
            : PayoutProvider.stripe,
        amountCents: amountCents,
        currency: currency,
        arrivalDate: DateTime.parse(arrivalDate),
        reconciliationStatus: reconciliationStatus == 'reconciled'
            ? PayoutReconciliationStatus.reconciled
            : PayoutReconciliationStatus.toVerify,
        internalPaymentsTotalCents: internalPaymentsTotalCents,
      );
}
