import 'package:nubia_domain/src/entities/cabinet_billing_stats.dart';

class CabinetBillingStatsDto {
  final int revenueCollectedCents;
  final int outstandingCents;
  final double? conversionRate;
  final int signedCount;
  final int sentTotal;

  const CabinetBillingStatsDto({
    required this.revenueCollectedCents,
    required this.outstandingCents,
    this.conversionRate,
    required this.signedCount,
    required this.sentTotal,
  });

  factory CabinetBillingStatsDto.fromJson(Map<String, dynamic> json) =>
      CabinetBillingStatsDto(
        revenueCollectedCents: json['revenue_collected_cents'] as int,
        outstandingCents: json['outstanding_cents'] as int,
        conversionRate: (json['conversion_rate'] as num?)?.toDouble(),
        signedCount: json['signed_count'] as int,
        sentTotal: json['sent_total'] as int,
      );

  CabinetBillingStats toDomain() => CabinetBillingStats(
        revenueCollectedCents: revenueCollectedCents,
        outstandingCents: outstandingCents,
        conversionRate: conversionRate,
        signedCount: signedCount,
        sentTotal: sentTotal,
      );
}
