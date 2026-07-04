import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/account_setup/account_setup_cubit.dart';
import 'package:app_patient/features/account_setup/account_setup_page.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockUpdateAccountUseCase extends Mock implements UpdateAccountUseCase {}

class MockAccountSetupCubit extends MockCubit<AccountSetupState>
    implements AccountSetupCubit {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _dob = DateTime(1990, 6, 15);

const _account = PatientAccount(
  id: 'p-1',
  firstName: 'Alice',
  lastName: 'Martin',
  email: 'alice@example.com',
  phone: '+33612345678',
);

// ---------------------------------------------------------------------------
// Widget helpers
// ---------------------------------------------------------------------------

Widget _wrap(AccountSetupCubit cubit) => BlocProvider<AccountSetupCubit>.value(
      value: cubit,
      child: MaterialApp(
        theme: NubiaTheme.light,
        home: const AccountSetupPage(),
      ),
    );

FilledButton _submitButton(WidgetTester tester) => tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Continuer'),
        matching: find.byType(FilledButton),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── Cubit tests ────────────────────────────────────────────────────────────

  group('AccountSetupCubit', () {
    late MockUpdateAccountUseCase mockUseCase;

    setUp(() {
      mockUseCase = MockUpdateAccountUseCase();
    });

    AccountSetupCubit makeCubit() =>
        AccountSetupCubit(updateAccount: mockUseCase);

    blocTest<AccountSetupCubit, AccountSetupState>(
      'émet [Loading, Success] quand le PATCH réussit',
      build: () {
        when(
          () => mockUseCase(
            firstName: any(named: 'firstName'),
            lastName: any(named: 'lastName'),
            phone: any(named: 'phone'),
            dateOfBirth: any(named: 'dateOfBirth'),
          ),
        ).thenAnswer((_) async => const Right(_account));
        return makeCubit();
      },
      act: (c) => c.submit(
        firstName: 'Alice',
        lastName: 'Martin',
        phone: '+33612345678',
        dateOfBirth: _dob,
      ),
      expect: () => [isA<AccountSetupLoading>(), isA<AccountSetupSuccess>()],
      verify: (_) => verify(
        () => mockUseCase(
          firstName: 'Alice',
          lastName: 'Martin',
          phone: '+33612345678',
          dateOfBirth: _dob,
        ),
      ).called(1),
    );

    blocTest<AccountSetupCubit, AccountSetupState>(
      'émet [Loading, Failure] quand le PATCH échoue',
      build: () {
        when(
          () => mockUseCase(
            firstName: any(named: 'firstName'),
            lastName: any(named: 'lastName'),
            phone: any(named: 'phone'),
            dateOfBirth: any(named: 'dateOfBirth'),
          ),
        ).thenAnswer(
          (_) async => const Left(
            ServerFailure(message: 'Erreur serveur.', statusCode: 500),
          ),
        );
        return makeCubit();
      },
      act: (c) => c.submit(
        firstName: 'Alice',
        lastName: 'Martin',
        phone: '+33612345678',
        dateOfBirth: _dob,
      ),
      expect: () => [
        isA<AccountSetupLoading>(),
        isA<AccountSetupFailure>()
            .having((s) => s.message, 'message', 'Erreur serveur.'),
      ],
    );

    blocTest<AccountSetupCubit, AccountSetupState>(
      'émet [Loading, Failure] sur erreur réseau',
      build: () {
        when(
          () => mockUseCase(
            firstName: any(named: 'firstName'),
            lastName: any(named: 'lastName'),
            phone: any(named: 'phone'),
            dateOfBirth: any(named: 'dateOfBirth'),
          ),
        ).thenAnswer((_) async => const Left(NetworkFailure()));
        return makeCubit();
      },
      act: (c) => c.submit(
        firstName: 'Alice',
        lastName: 'Martin',
        phone: '+33612345678',
        dateOfBirth: _dob,
      ),
      expect: () => [
        isA<AccountSetupLoading>(),
        isA<AccountSetupFailure>().having(
          (s) => s.message,
          'message',
          'Erreur réseau. Vérifiez votre connexion.',
        ),
      ],
    );
  });

  // ── Widget tests ───────────────────────────────────────────────────────────

  group('AccountSetupPage', () {
    late MockAccountSetupCubit cubit;

    setUp(() {
      cubit = MockAccountSetupCubit();
      when(() => cubit.state).thenReturn(const AccountSetupIdle());
    });

    testWidgets('formulaire vide → bouton désactivé', (tester) async {
      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      expect(_submitButton(tester).onPressed, isNull);
    });

    testWidgets('formulaire sans date → bouton désactivé', (tester) async {
      await tester.pumpWidget(_wrap(cubit));

      await tester.enterText(
          find.ancestor(
              of: find.text('Prénom'), matching: find.byType(TextField)),
          'Alice');
      await tester.pump();
      await tester.enterText(
          find.ancestor(of: find.text('Nom'), matching: find.byType(TextField)),
          'Martin');
      await tester.pump();
      await tester.enterText(
          find.ancestor(
              of: find.text('Téléphone'), matching: find.byType(TextField)),
          '+33612345678');
      await tester.pump();

      expect(_submitButton(tester).onPressed, isNull);
    });

    testWidgets('AccountSetupFailure → snackbar affiché', (tester) async {
      whenListen(
        cubit,
        Stream.fromIterable([
          const AccountSetupFailure('Erreur serveur.'),
        ]),
        initialState: const AccountSetupIdle(),
      );

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      expect(find.text('Erreur serveur.'), findsOneWidget);
    });

    testWidgets('AccountSetupIdle : scaffold et formulaire visibles',
        (tester) async {
      when(() => cubit.state).thenReturn(const AccountSetupIdle());
      await tester.pumpWidget(_wrap(cubit));

      expect(find.byKey(const Key('account_setup_scaffold')), findsOneWidget);
      expect(find.text('Mon profil'), findsOneWidget);
      expect(find.text('Continuer'), findsOneWidget);
    });

    testWidgets('AccountSetupLoading : bouton en cours de chargement',
        (tester) async {
      when(() => cubit.state).thenReturn(const AccountSetupLoading());
      await tester.pumpWidget(_wrap(cubit));

      expect(find.byKey(const Key('account_setup_scaffold')), findsOneWidget);
      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('AccountSetupSuccess : scaffold visible avant redirection',
        (tester) async {
      when(() => cubit.state).thenReturn(const AccountSetupSuccess());
      await tester.pumpWidget(_wrap(cubit));

      expect(find.byKey(const Key('account_setup_scaffold')), findsOneWidget);
      expect(find.text('Mon profil'), findsOneWidget);
    });

    testWidgets('AccountSetupFailure statique : formulaire visible',
        (tester) async {
      when(() => cubit.state)
          .thenReturn(const AccountSetupFailure('Erreur réseau.'));
      await tester.pumpWidget(_wrap(cubit));

      expect(find.byKey(const Key('account_setup_scaffold')), findsOneWidget);
      expect(find.text('Mon profil'), findsOneWidget);
    });
  });
}
