import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_pharmacie/features/stock/stock_delay.dart';

StockRequest _request({
  required StockRequestStatus status,
  required DateTime createdAt,
}) =>
    StockRequest(
      id: 'r1',
      pharmacyId: 'p1',
      cabinetName: 'Cabinet Dupont',
      items: const [],
      status: status,
      createdAt: createdAt,
    );

void main() {
  final now = DateTime(2026, 8, 13, 10);

  group('stockDelayOf', () {
    test('sent depuis 2 h → « Attend 2 h », ton soon', () {
      final request = _request(
        status: StockRequestStatus.sent,
        createdAt: DateTime(2026, 8, 13, 8),
      );

      final delay = stockDelayOf(request, now: now);

      expect(delay.label, 'Attend 2 h');
      expect(delay.tone, StockDelayTone.soon);
    });

    test('sent depuis 2 h 45 → « Attend 2 h 45 »', () {
      final request = _request(
        status: StockRequestStatus.sent,
        createdAt: DateTime(2026, 8, 13, 7, 15),
      );

      final delay = stockDelayOf(request, now: now);

      expect(delay.label, 'Attend 2 h 45');
      expect(delay.tone, StockDelayTone.soon);
    });

    test('sent depuis moins d\'1 h → « Attend N min »', () {
      final request = _request(
        status: StockRequestStatus.sent,
        createdAt: DateTime(2026, 8, 13, 9, 40),
      );

      final delay = stockDelayOf(request, now: now);

      expect(delay.label, 'Attend 20 min');
      expect(delay.tone, StockDelayTone.soon);
    });

    test('sent depuis ≥ 1 j → « Attend 1 j », ton late (rouge)', () {
      final request = _request(
        status: StockRequestStatus.sent,
        createdAt: DateTime(2026, 8, 12, 9),
      );

      final delay = stockDelayOf(request, now: now);

      expect(delay.label, 'Attend 1 j');
      expect(delay.tone, StockDelayTone.late);
    });

    test('sent depuis 3 j → « Attend 3 j »', () {
      final request = _request(
        status: StockRequestStatus.sent,
        createdAt: DateTime(2026, 8, 10, 9),
      );

      expect(stockDelayOf(request, now: now).label, 'Attend 3 j');
    });

    test('accepted → « Acceptée le JJ/MM »', () {
      final request = _request(
        status: StockRequestStatus.accepted,
        createdAt: DateTime(2026, 8, 8),
      );

      final delay = stockDelayOf(request, now: now);

      expect(delay.label, 'Acceptée le 08/08');
      expect(delay.tone, StockDelayTone.neutral);
    });

    test('fulfilled → « Honorée le JJ/MM »', () {
      final request = _request(
        status: StockRequestStatus.fulfilled,
        createdAt: DateTime(2026, 8, 6),
      );

      expect(stockDelayOf(request, now: now).label, 'Honorée le 06/08');
    });

    test('rejected → « Refusée le JJ/MM »', () {
      final request = _request(
        status: StockRequestStatus.rejected,
        createdAt: DateTime(2026, 8, 4),
      );

      expect(stockDelayOf(request, now: now).label, 'Refusée le 04/08');
    });
  });
}
