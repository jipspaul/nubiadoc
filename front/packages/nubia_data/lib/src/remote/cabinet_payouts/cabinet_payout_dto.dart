import 'package:nubia_domain/src/entities/cabinet_payout.dart';

class InternalPaymentDto {
  final String patientName;
  final String time;
  final int amountCents;
  final String methodLabel;
  final bool reconcilableByProvider;

  const InternalPaymentDto({
    required this.patientName,
    required this.time,
    required this.amountCents,
    required this.methodLabel,
    required this.reconcilableByProvider,
  });

  factory InternalPaymentDto.fromJson(Map<String, dynamic> json) =>
      InternalPaymentDto(
        patientName: json['patient_name'] as String,
        time: json['time'] as String,
        amountCents: json['amount_cents'] as int,
        methodLabel: json['method_label'] as String,
        reconcilableByProvider: json['reconcilable_by_provider'] as bool,
      );

  InternalPayment toDomain() => InternalPayment(
        patientName: patientName,
        time: time,
        amountCents: amountCents,
        methodLabel: methodLabel,
        reconcilableByProvider: reconcilableByProvider,
      );
}

class CabinetPayoutDto {
  final String id;
  final String provider;
  final int amountCents;
  final String currency;
  final String arrivalDate;
  final String reconciliationStatus;
  final int internalPaymentsTotalCents;
  final List<InternalPaymentDto> internalPayments;

  const CabinetPayoutDto({
    required this.id,
    required this.provider,
    required this.amountCents,
    required this.currency,
    required this.arrivalDate,
    required this.reconciliationStatus,
    required this.internalPaymentsTotalCents,
    this.internalPayments = const [],
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
        internalPayments: ((json['internal_payments'] as List<dynamic>?) ??
                const [])
            .map((e) => InternalPaymentDto.fromJson(e as Map<String, dynamic>))
            .toList(),
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
        internalPayments: internalPayments.map((p) => p.toDomain()).toList(),
      );
}
