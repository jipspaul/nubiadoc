import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/dashboard/cash_collection_cubit.dart';

class _MockGetSummary extends Mock implements GetCashCollectionSummaryUseCase {}

const _summary = CashCollectionSummary(
  collectedTodayCents: 184200,
  collectedTodayPaymentCount: 7,
  remainingTodayCents: 36050,
  remainingTodayPatientCount: 2,
  closingHour: 19,
  unpaidCents: 291800,
  unpaidPatientCount: 7,
);

void main() {
  group('CashCollectionCubit', () {
    late _MockGetSummary getSummary;

    setUp(() {
      getSummary = _MockGetSummary();
    });

    blocTest<CashCollectionCubit, CashCollectionState>(
      '#5382 : charge le résumé de caisse du jour',
      build: () {
        when(() => getSummary()).thenAnswer((_) async => const Right(_summary));
        return CashCollectionCubit(getSummary: getSummary);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const CashCollectionLoading(),
        const CashCollectionLoaded(summary: _summary),
      ],
    );

    blocTest<CashCollectionCubit, CashCollectionState>(
      'échec réseau → CashCollectionError (pas un faux 0)',
      build: () {
        when(() => getSummary())
            .thenAnswer((_) async => const Left(NetworkFailure()));
        return CashCollectionCubit(getSummary: getSummary);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const CashCollectionLoading(),
        isA<CashCollectionError>(),
      ],
    );
  });
}
