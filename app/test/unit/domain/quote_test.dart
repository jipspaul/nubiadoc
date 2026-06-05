import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_patient/domain/entities/quote.dart';

void main() {
  group('Quote', () {
    test('canSign is true only for sent status', () {
      final quote = Quote(
        id: 'q1',
        cabinetId: 'cab1',
        practitionerName: 'Dr. Test',
        items: const [],
        totalCents: 125000,
        patientShareCents: 38000,
        depositCents: 38000,
        status: QuoteStatus.sent,
        createdAt: DateTime.now(),
      );
      expect(quote.canSign, isTrue);
    });

    test('canSign is false for already-signed quote', () {
      final quote = Quote(
        id: 'q2',
        cabinetId: 'cab1',
        practitionerName: 'Dr. Test',
        items: const [],
        totalCents: 125000,
        patientShareCents: 38000,
        depositCents: 38000,
        status: QuoteStatus.signed,
        createdAt: DateTime.now(),
      );
      expect(quote.canSign, isFalse);
    });
  });
}
