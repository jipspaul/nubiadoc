import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/coverage_setup/coverage_setup_cubit.dart';
import 'package:app_patient/features/coverage_setup/coverage_setup_page.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockUpdateCoverageUseCase extends Mock implements UpdateCoverageUseCase {}

class MockGetCoverageUseCase extends Mock implements GetCoverageUseCase {}

class MockCoverageSetupCubit extends MockCubit<CoverageSetupState>
    implements CoverageSetupCubit {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _coverage = HealthCoverage(
  regime: HealthInsuranceRegime.regimeGeneral,
  insuranceName: 'MGEN',
  memberNumber: '123456',
);

// ---------------------------------------------------------------------------
// Widget helpers
// ---------------------------------------------------------------------------

Widget _wrap(CoverageSetupCubit cubit) =>
    BlocProvider<CoverageSetupCubit>.value(
      value: cubit,
      child: MaterialApp(
        theme: NubiaTheme.light,
        home: const CoverageSetupPage(),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(HealthInsuranceRegime.regimeGeneral);
  });

  group('CoverageSetupCubit', () {
    late MockUpdateCoverageUseCase mockUseCase;
    late MockGetCoverageUseCase mockGetUseCase;

    setUp(() {
      mockUseCase = MockUpdateCoverageUseCase();
      mockGetUseCase = MockGetCoverageUseCase();
    });

    CoverageSetupCubit makeCubit() => CoverageSetupCubit(
          getCoverage: mockGetUseCase,
          updateCoverage: mockUseCase,
        );

    // Régression #3842 : cet écran est réutilisé pour éditer une couverture
    // existante depuis le Profil (pas seulement l'onboarding) — il doit
    // charger et préremplir la couverture réelle, pas afficher un formulaire
    // vierge qui écraserait silencieusement les données au premier submit.
    blocTest<CoverageSetupCubit, CoverageSetupState>(
      'load émet [Loading, Loaded(coverage)] quand le GET réussit',
      build: () {
        when(() => mockGetUseCase())
            .thenAnswer((_) async => const Right(_coverage));
        return makeCubit();
      },
      act: (c) => c.load(),
      expect: () => [
        isA<CoverageSetupLoading>(),
        isA<CoverageSetupLoaded>().having(
          (s) => s.coverage,
          'coverage',
          _coverage,
        ),
      ],
    );

    blocTest<CoverageSetupCubit, CoverageSetupState>(
      'load émet [Loading, Idle] quand le GET échoue (dégradation gracieuse)',
      build: () {
        when(() => mockGetUseCase())
            .thenAnswer((_) async => const Left(NetworkFailure()));
        return makeCubit();
      },
      act: (c) => c.load(),
      expect: () => [isA<CoverageSetupLoading>(), isA<CoverageSetupIdle>()],
    );

    blocTest<CoverageSetupCubit, CoverageSetupState>(
      'skip émet [Success] sans appeler le use case',
      build: makeCubit,
      act: (c) => c.skipStep(),
      expect: () => [isA<CoverageSetupSuccess>()],
      verify: (_) => verifyNever(
        () => mockUseCase(
          regime: any(named: 'regime'),
          thirdPartyPayment: any(named: 'thirdPartyPayment'),
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
          thirdPartyPayment: false,
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
      act: (c) => c.submit(regime: HealthInsuranceRegime.css),
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
      act: (c) => c.submit(regime: HealthInsuranceRegime.ame),
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

  group('CoverageSetupPage', () {
    late MockCoverageSetupCubit cubit;

    setUp(() {
      cubit = MockCoverageSetupCubit();
      when(() => cubit.state).thenReturn(const CoverageSetupIdle());
      when(() => cubit.load()).thenAnswer((_) async {});
      whenListen(
        cubit,
        Stream<CoverageSetupState>.empty(),
        initialState: const CoverageSetupIdle(),
      );
    });

    testWidgets('affiche les radios de régime', (tester) async {
      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      expect(find.text('Régime général'), findsOneWidget);
      expect(find.text('AME'), findsOneWidget);
      expect(find.text('CSS'), findsOneWidget);
    });

    testWidgets('appelle load() au chargement de l\'écran (#3842)',
        (tester) async {
      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      verify(() => cubit.load()).called(1);
    });

    testWidgets('CoverageSetupFailure → snackbar affiché', (tester) async {
      whenListen(
        cubit,
        Stream.fromIterable([
          const CoverageSetupFailure('Erreur serveur.'),
        ]),
        initialState: const CoverageSetupIdle(),
      );

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      expect(find.text('Erreur serveur.'), findsOneWidget);
    });

    // Régression #3842 : la fiche patient chargeait le formulaire vierge
    // (Régime général, mutuelle/numéro vides) même quand une couverture
    // réelle existait côté serveur — un « Enregistrer » sans y toucher
    // écrasait silencieusement la vraie couverture.
    testWidgets('CoverageSetupLoaded → préremplit régime + mutuelle + numéro',
        (tester) async {
      whenListen(
        cubit,
        Stream.fromIterable([const CoverageSetupLoaded(_coverage)]),
        initialState: const CoverageSetupIdle(),
      );

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      expect(find.text('MGEN'), findsOneWidget);
      expect(find.text('123456'), findsOneWidget);
      final radio = tester.widget<RadioGroup<HealthInsuranceRegime>>(
        find.byType(RadioGroup<HealthInsuranceRegime>),
      );
      expect(radio.groupValue, HealthInsuranceRegime.regimeGeneral);
    });
  });
}
