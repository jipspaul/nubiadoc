import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/consents/consents_cubit.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockListConsentsUseCase extends Mock implements ListConsentsUseCase {}

class MockSetConsentUseCase extends Mock implements SetConsentUseCase {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _consents = [
  Consent(purpose: 'marketing', granted: false),
  Consent(purpose: 'soins', granted: true),
];

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockListConsentsUseCase mockList;
  late MockSetConsentUseCase mockSet;

  setUp(() {
    mockList = MockListConsentsUseCase();
    mockSet = MockSetConsentUseCase();
  });

  ConsentsCubit makeCubit() => ConsentsCubit(list: mockList, set: mockSet);

  group('ConsentsCubit', () {
    blocTest<ConsentsCubit, ConsentsState>(
      'load() émet ConsentsError (plein écran) sur échec de chargement',
      build: () {
        when(() => mockList())
            .thenAnswer((_) async => const Left(NetworkFailure()));
        return makeCubit();
      },
      act: (c) => c.load(),
      expect: () => [
        isA<ConsentsLoading>(),
        isA<ConsentsError>(),
      ],
    );

    blocTest<ConsentsCubit, ConsentsState>(
      // #5215 — un échec de toggle() ne doit jamais émettre ConsentsError
      // (plein écran) : la liste reste affichée, la bascule revient à son
      // état serveur, l'erreur est portée par ConsentsLoaded.toggleError.
      'toggle() en échec reste sur ConsentsLoaded avec toggleError, sans ConsentsError',
      seed: () => const ConsentsLoaded(_consents),
      build: () {
        when(() => mockSet(purpose: 'marketing', granted: true)).thenAnswer(
          (_) async => const Left(
            ServerFailure(message: 'Échec de la mise à jour.'),
          ),
        );
        return makeCubit();
      },
      act: (c) => c.toggle('marketing', true),
      expect: () => [
        isA<ConsentsLoaded>()
            .having((s) => s.consents, 'consents', _consents)
            .having((s) => s.pending, 'pending', 'marketing'),
        isA<ConsentsLoaded>()
            .having((s) => s.consents, 'consents', _consents)
            .having((s) => s.pending, 'pending', isNull)
            .having(
              (s) => s.toggleError,
              'toggleError',
              'Échec de la mise à jour.',
            ),
      ],
    );

    blocTest<ConsentsCubit, ConsentsState>(
      'toggle() en succès recharge la liste depuis le serveur',
      seed: () => const ConsentsLoaded(_consents),
      build: () {
        when(() => mockSet(purpose: 'marketing', granted: true))
            .thenAnswer((_) async => const Right(null));
        when(() => mockList()).thenAnswer(
          (_) async => const Right([
            Consent(purpose: 'marketing', granted: true),
            Consent(purpose: 'soins', granted: true),
          ]),
        );
        return makeCubit();
      },
      act: (c) => c.toggle('marketing', true),
      expect: () => [
        isA<ConsentsLoaded>().having((s) => s.pending, 'pending', 'marketing'),
        isA<ConsentsLoading>(),
        isA<ConsentsLoaded>().having(
          (s) => s.consents.firstWhere((c) => c.purpose == 'marketing').granted,
          'marketing granted',
          true,
        ),
      ],
    );
  });
}
