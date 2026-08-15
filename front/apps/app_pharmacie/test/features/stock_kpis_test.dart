import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_pharmacie/features/stock/widgets/stock_kpis.dart';

StockRequest _request({
  required StockRequestStatus status,
  DateTime? fulfilledAt,
  String? cabinetName,
}) =>
    StockRequest(
      id: 'r1',
      pharmacyId: 'p1',
      cabinetName: cabinetName,
      items: const [],
      status: status,
      createdAt: DateTime(2026, 7, 1),
      fulfilledAt: fulfilledAt,
    );

void main() {
  final august = DateTime(2026, 8, 14, 10);

  test(
    'fulfilledCount ne compte que les demandes honorées dans le mois de référence',
    () {
      final kpis = StockKpis.fromRequests(
        [
          // Créée en juillet, honorée en août → comptée.
          _request(
            status: StockRequestStatus.fulfilled,
            fulfilledAt: DateTime(2026, 8, 3),
          ),
          // Honorée en juillet → pas comptée en août.
          _request(
            status: StockRequestStatus.fulfilled,
            fulfilledAt: DateTime(2026, 7, 30),
          ),
          // Honorée l'an dernier en août → pas comptée (mois ET année).
          _request(
            status: StockRequestStatus.fulfilled,
            fulfilledAt: DateTime(2025, 8, 3),
          ),
          _request(status: StockRequestStatus.sent),
          _request(status: StockRequestStatus.accepted),
        ],
        now: august,
      );

      expect(kpis.fulfilledCount, 1);
      expect(kpis.toRespondCount, 1);
      expect(kpis.toDeliverCount, 1);
    },
  );

  test(
    'fulfilledCount exclut une demande fulfilled sans fulfilledAt (donnée absente)',
    () {
      final kpis = StockKpis.fromRequests(
        [_request(status: StockRequestStatus.fulfilled)],
        now: august,
      );

      expect(kpis.fulfilledCount, 0);
    },
  );
}
