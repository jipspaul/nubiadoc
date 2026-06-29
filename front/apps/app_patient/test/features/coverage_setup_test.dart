import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/coverage_setup/coverage_setup_cubit.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockUpdateCoverageUseCase extends Mock implements UpdateCoverageUseCase {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _coverage = HealthCoverage(regime: HealthInsuranceRegime.regimeGeneral);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(HealthInsuranceRegime.regimeGeneral);
  });

  group('CoverageSetupCubit', () {
    late MockUpdateCoverageUseCase mockUseCase;

    setUp(() {
      mockUseCase = MockUpdateCoverageUseCase();
    });

    CoverageSetupCubit makeCubit() =>
        CoverageSetupCubit(updateCoverage: mockUseCase);

    blocTest<CoverageSetupCubit, CoverageSetupState>(
      'skip émet [Success] sans appeler le use case',
      build: makeCubit,
      act: (c) => c.skip(),
      expect: () => [isA<CoverageSetupSuccess>()],
      verify: (_) => verifyNever(
        () => mockUseCase(
          regime: any(named: 'regime'),
        ),
      ),
    );

    blocTest<CoverageSetupCubit, CoverageSetupState>(
      'submit émet [Loading, Success] quand le PATCH réussit',
      build: () {
        when(
          () => mockUseCase(
            regime: any(named: 'regime'),
            amc: any(named: 'amc'),
            numeroAdherent: any(named: 'numeroAdherent'),
            thirdPartyPayment: any(named: 'thirdPartyPayment'),
          ),
        ).thenAnswer((_) async => const Right(_coverage));
        return makeCubit();
      },
      act: (c) => c.submit(
        regime: HealthInsuranceRegime.regimeGeneral,
        amc: 'MGEN',
        numeroAdherent: '123456',
      ),
      expect: () => [isA<CoverageSetupLoading>(), isA<CoverageSetupSuccess>()],
      verify: (_) => verify(
        () => mockUseCase(
          regime: HealthInsuranceRegime.regimeGeneral,
          amc: 'MGEN',
          numeroAdherent: '123456',
        ),
      ).called(1),
    );

    blocTest<CoverageSetupCubit, CoverageSetupState>(
      'submit émet [Loading, Failure] quand le PATCH échoue',
      build: () {
        when(
          () => mockUseCase(
            regime: any(named: 'regime'),
            amc: any(named: 'amc'),
            numeroAdherent: any(named: 'numeroAdherent'),
            thirdPartyPayment: any(named: 'thirdPartyPayment'),
          ),
        ).thenAnswer(
          (_) async => const Left(
            ServerFailure(message: 'Erreur serveur.', statusCode: 500),
          ),
        );
        return makeCubit();
      },
      act: (c) => c.submit(
        regime: HealthInsuranceRegime.css,
      ),
      expect: () => [
        isA<CoverageSetupLoading>(),
        isA<CoverageSetupFailure>()
            .having((s) => s.message, 'message', 'Erreur serveur.'),
      ],
    );

    blocTest<CoverageSetupCubit, CoverageSetupState>(
      'submit émet [Loading, Failure] sur erreur réseau',
      build: () {
        when(
          () => mockUseCase(
            regime: any(named: 'regime'),
            amc: any(named: 'amc'),
            numeroAdherent: any(named: 'numeroAdherent'),
            thirdPartyPayment: any(named: 'thirdPartyPayment'),
          ),
        ).thenAnswer((_) async => const Left(NetworkFailure()));
        return makeCubit();
      },
      act: (c) => c.submit(
        regime: HealthInsuranceRegime.ame,
      ),
      expect: () => [
        isA<CoverageSetupLoading>(),
        isA<CoverageSetupFailure>().having(
          (s) => s.message,
          'message',
          'Erreur réseau. Vérifiez votre connexion.',
        ),
      ],
    );
  });
}
