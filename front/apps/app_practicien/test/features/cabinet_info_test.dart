import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/cabinet/cabinet_info_cubit.dart';
import 'package:app_practicien/features/cabinet/cabinet_info_page.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockUpdateCabinetUseCase extends Mock implements UpdateCabinetUseCase {}

class MockCabinetInfoCubit extends MockCubit<CabinetInfoState>
    implements CabinetInfoCubit {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(CabinetInfoCubit cubit) => BlocProvider<CabinetInfoCubit>.value(
      value: cubit,
      child: MaterialApp(
        theme: NubiaTheme.light,
        home: const CabinetInfoPage(),
      ),
    );

FilledButton _submitButton(WidgetTester tester) => tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Enregistrer'),
        matching: find.byType(FilledButton),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(const UpdateCabinetRequest());
  });

  // ── Cubit tests ────────────────────────────────────────────────────────────

  group('CabinetInfoCubit', () {
    late MockUpdateCabinetUseCase mockUseCase;

    setUp(() {
      mockUseCase = MockUpdateCabinetUseCase();
    });

    CabinetInfoCubit makeCubit() =>
        CabinetInfoCubit(updateCabinet: mockUseCase);

    blocTest<CabinetInfoCubit, CabinetInfoState>(
      'émet [Loading, Success] quand le PATCH réussit',
      build: () {
        when(() => mockUseCase(any())).thenAnswer(
          (_) async => const Right(null),
        );
        return makeCubit();
      },
      act: (c) => c.submit(
        name: 'Cabinet Nubia',
        address: '12 rue de la Paix, Paris',
        phone: '0612345678',
        siret: '12345678901234',
      ),
      expect: () => [isA<CabinetInfoLoading>(), isA<CabinetInfoSuccess>()],
      verify: (_) => verify(() => mockUseCase(any())).called(1),
    );

    blocTest<CabinetInfoCubit, CabinetInfoState>(
      'émet [Loading, Failure] quand le PATCH échoue',
      build: () {
        when(() => mockUseCase(any())).thenAnswer(
          (_) async => const Left(
            ServerFailure(message: 'Erreur serveur.', statusCode: 500),
          ),
        );
        return makeCubit();
      },
      act: (c) => c.submit(
        name: 'Cabinet Nubia',
        address: '12 rue de la Paix, Paris',
        phone: '0612345678',
      ),
      expect: () => [
        isA<CabinetInfoLoading>(),
        isA<CabinetInfoFailure>()
            .having((s) => s.message, 'message', 'Erreur serveur.'),
      ],
    );

    blocTest<CabinetInfoCubit, CabinetInfoState>(
      'émet [Loading, Failure] sur erreur réseau',
      build: () {
        when(() => mockUseCase(any())).thenAnswer(
          (_) async => const Left(NetworkFailure()),
        );
        return makeCubit();
      },
      act: (c) => c.submit(
        name: 'Cabinet Nubia',
        address: '12 rue de la Paix, Paris',
        phone: '0612345678',
      ),
      expect: () => [
        isA<CabinetInfoLoading>(),
        isA<CabinetInfoFailure>().having(
          (s) => s.message,
          'message',
          'Erreur réseau. Vérifiez votre connexion.',
        ),
      ],
    );
  });

  // ── Widget tests ───────────────────────────────────────────────────────────

  group('CabinetInfoPage', () {
    late MockCabinetInfoCubit cubit;

    setUp(() {
      cubit = MockCabinetInfoCubit();
      when(() => cubit.state).thenReturn(const CabinetInfoIdle());
    });

    testWidgets('formulaire vide → bouton désactivé', (tester) async {
      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      expect(_submitButton(tester).onPressed, isNull);
    });

    testWidgets('formulaire complet valide → bouton activé', (tester) async {
      await tester.pumpWidget(_wrap(cubit));

      await tester.enterText(
        find.ancestor(
            of: find.text('Nom du cabinet'), matching: find.byType(TextField)),
        'Cabinet Nubia',
      );
      await tester.pump();
      await tester.enterText(
        find.ancestor(
            of: find.text('Adresse'), matching: find.byType(TextField)),
        '12 rue de la Paix, Paris',
      );
      await tester.pump();
      await tester.enterText(
        find.ancestor(
            of: find.text('Téléphone'), matching: find.byType(TextField)),
        '0612345678',
      );
      await tester.pump();

      expect(_submitButton(tester).onPressed, isNotNull);
    });

    testWidgets('CabinetInfoLoading → spinner affiché, bouton désactivé',
        (tester) async {
      when(() => cubit.state).thenReturn(const CabinetInfoLoading());
      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('CabinetInfoFailure → snackbar affiché', (tester) async {
      whenListen(
        cubit,
        Stream.fromIterable([
          const CabinetInfoFailure('Erreur serveur.'),
        ]),
        initialState: const CabinetInfoIdle(),
      );

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      expect(find.text('Erreur serveur.'), findsOneWidget);
    });

    testWidgets(
        'CabinetInfoSuccess → formulaire toujours affiché (listener gère la navigation)',
        (tester) async {
      when(() => cubit.state).thenReturn(const CabinetInfoSuccess());
      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      expect(find.byKey(const Key('cabinet_setup_scaffold')), findsOneWidget);
      expect(find.text('Enregistrer'), findsOneWidget);
    });
  });
}
