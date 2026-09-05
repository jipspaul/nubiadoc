import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/dashboard/expiring_quotes_summary_cubit.dart';

class _MockListQuotes extends Mock implements ListCabinetQuotesUseCase {}

CabinetQuote _quote(
  String id, {
  required CabinetQuoteStatus status,
  String patientName = 'Patient',
  DateTime? expiresAt,
}) =>
    CabinetQuote(
      id: id,
      quoteRef: id,
      cabinetId: 'cab',
      patientId: 'p-$id',
      patientName: patientName,
      totalCents: 10000,
      patientShareCents: 5000,
      status: status,
      createdAt: DateTime(2026, 1, 1),
      expiresAt: expiresAt,
    );

void main() {
  group('ExpiringQuotesSummaryCubit', () {
    late _MockListQuotes listQuotes;

    setUp(() {
      listQuotes = _MockListQuotes();
    });

    blocTest<ExpiringQuotesSummaryCubit, ExpiringQuotesSummaryState>(
      '#5377 : ne garde que les devis envoyés expirant dans les 7 jours, '
      'triés par échéance croissante',
      build: () {
        final now = DateTime.now();
        when(() => listQuotes()).thenAnswer(
          (_) async => Right([
            _quote(
              'q1',
              status: CabinetQuoteStatus.sent,
              patientName: 'Nina Lopez',
              expiresAt: now.add(const Duration(days: 5)),
            ),
            _quote(
              'q2',
              status: CabinetQuoteStatus.sent,
              patientName: 'Julie Martin',
              expiresAt: now.add(const Duration(days: 1)),
            ),
            // Signé : jamais retenu, même avec une échéance proche.
            _quote(
              'q3',
              status: CabinetQuoteStatus.signed,
              expiresAt: now.add(const Duration(days: 2)),
            ),
            // Échéance trop lointaine : hors fenêtre des 7 jours.
            _quote(
              'q4',
              status: CabinetQuoteStatus.sent,
              expiresAt: now.add(const Duration(days: 30)),
            ),
            // Déjà expiré : hors fenêtre (avant maintenant).
            _quote(
              'q5',
              status: CabinetQuoteStatus.sent,
              expiresAt: now.subtract(const Duration(days: 1)),
            ),
          ]),
        );
        return ExpiringQuotesSummaryCubit(listQuotes: listQuotes);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const ExpiringQuotesSummaryLoading(),
        isA<ExpiringQuotesSummaryLoaded>().having(
            (s) => s.quotes.map((q) => q.id).toList(), 'ids', ['q2', 'q1']),
      ],
    );

    blocTest<ExpiringQuotesSummaryCubit, ExpiringQuotesSummaryState>(
      'aucun devis expirant → liste vide',
      build: () {
        when(() => listQuotes()).thenAnswer((_) async => const Right([]));
        return ExpiringQuotesSummaryCubit(listQuotes: listQuotes);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const ExpiringQuotesSummaryLoading(),
        const ExpiringQuotesSummaryLoaded(quotes: []),
      ],
    );

    blocTest<ExpiringQuotesSummaryCubit, ExpiringQuotesSummaryState>(
      'échec réseau → ExpiringQuotesSummaryError (pas une liste vide)',
      build: () {
        when(() => listQuotes())
            .thenAnswer((_) async => const Left(NetworkFailure()));
        return ExpiringQuotesSummaryCubit(listQuotes: listQuotes);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const ExpiringQuotesSummaryLoading(),
        isA<ExpiringQuotesSummaryError>(),
      ],
    );
  });
}
