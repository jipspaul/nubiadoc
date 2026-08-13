import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_pharmacie/features/devis/quote_delay.dart';

PharmacyQuote _quote({
  required PharmacyQuoteStatus status,
  required DateTime createdAt,
  DateTime? sentAt,
  DateTime? decidedAt,
}) =>
    PharmacyQuote(
      id: 'q1',
      pharmacyId: 'p1',
      patientDisplayName: 'Jean D.',
      items: const [],
      totalCents: 0,
      status: status,
      createdAt: createdAt,
      sentAt: sentAt,
      decidedAt: decidedAt,
    );

void main() {
  final now = DateTime(2026, 8, 13, 10);

  group('quoteDelayOf', () {
    test('sent depuis 3 j → « Envoyé il y a 3 j », ton soon', () {
      final quote = _quote(
        status: PharmacyQuoteStatus.sent,
        createdAt: DateTime(2026, 8, 9),
        sentAt: DateTime(2026, 8, 10),
      );

      final delay = quoteDelayOf(quote, now: now);

      expect(delay.label, 'Envoyé il y a 3 j');
      expect(delay.tone, QuoteDelayTone.soon);
    });

    test('sent depuis 1 j → singulier « il y a 1 j »', () {
      final quote = _quote(
        status: PharmacyQuoteStatus.sent,
        createdAt: DateTime(2026, 8, 11),
        sentAt: DateTime(2026, 8, 12),
      );

      expect(quoteDelayOf(quote, now: now).label, 'Envoyé il y a 1 j');
    });

    test('draft créé ce matin (même jour, avant midi)', () {
      final quote = _quote(
        status: PharmacyQuoteStatus.draft,
        createdAt: DateTime(2026, 8, 13, 8),
      );

      final delay = quoteDelayOf(quote, now: now);

      expect(delay.label, 'Créé ce matin');
      expect(delay.tone, QuoteDelayTone.neutral);
    });

    test('accepted → « Accepté le JJ/MM » (date de decidedAt)', () {
      final quote = _quote(
        status: PharmacyQuoteStatus.accepted,
        createdAt: DateTime(2026, 8, 9),
        sentAt: DateTime(2026, 8, 9),
        decidedAt: DateTime(2026, 8, 10),
      );

      final delay = quoteDelayOf(quote, now: now);

      expect(delay.label, 'Accepté le 10/08');
      expect(delay.tone, QuoteDelayTone.neutral);
    });

    test('refused → « Refusé le JJ/MM »', () {
      final quote = _quote(
        status: PharmacyQuoteStatus.refused,
        createdAt: DateTime(2026, 7, 25),
        sentAt: DateTime(2026, 7, 25),
        decidedAt: DateTime(2026, 7, 26),
      );

      expect(quoteDelayOf(quote, now: now).label, 'Refusé le 26/07');
    });

    test('expired → « Expiré le JJ/MM », ton late (rouge)', () {
      final quote = _quote(
        status: PharmacyQuoteStatus.expired,
        createdAt: DateTime(2026, 8, 1),
        sentAt: DateTime(2026, 8, 1),
        decidedAt: DateTime(2026, 8, 11),
      );

      final delay = quoteDelayOf(quote, now: now);

      expect(delay.label, 'Expiré le 11/08');
      expect(delay.tone, QuoteDelayTone.late);
    });
  });
}
