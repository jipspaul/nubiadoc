import 'package:equatable/equatable.dart';

/// KPI de facturation du cabinet, #4153. Source :
/// `GET /v1/cabinet/stats/billing`.
class CabinetBillingStats extends Equatable {
  final int revenueCollectedCents;
  final int outstandingCents;
  final double? conversionRate;
  final int signedCount;
  final int sentTotal;

  const CabinetBillingStats({
    required this.revenueCollectedCents,
    required this.outstandingCents,
    this.conversionRate,
    required this.signedCount,
    required this.sentTotal,
  });

  @override
  List<Object?> get props => [
        revenueCollectedCents,
        outstandingCents,
        conversionRate,
        signedCount,
        sentTotal,
      ];
}
