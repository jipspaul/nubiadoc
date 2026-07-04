import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_patient/features/signup/signup_cubit.dart';
import 'package:app_patient/features/signup/signup_page.dart';
import 'package:app_patient/router/app_router.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockSignupCubit extends MockCubit<SignupState> implements SignupCubit {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(SignupCubit cubit) => BlocProvider<SignupCubit>.value(
      value: cubit,
      child: MaterialApp(
        theme: NubiaTheme.light,
        home: const SignupPage(),
      ),
    );

FilledButton _submitButton(WidgetTester tester) => tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Créer mon compte'),
        matching: find.byType(FilledButton),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SignupPage', () {
    late MockSignupCubit cubit;

    setUp(() {
      cubit = MockSignupCubit();
      when(() => cubit.state).thenReturn(const SignupIdle());
    });

    testWidgets('formulaire vide → bouton désactivé', (tester) async {
      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      expect(_submitButton(tester).onPressed, isNull);
    });

    testWidgets('formulaire valide → bouton activé', (tester) async {
      await tester.pumpWidget(_wrap(cubit));

      await tester.enterText(find.byType(TextField).at(0), 'alice@example.com');
      await tester.pump();

      await tester.enterText(find.byType(TextField).at(1), 'Secr3tABC');
      await tester.pump();

      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      expect(_submitButton(tester).onPressed, isNotNull);
    });

    // Non-régression #3100/#3022 (flow A) : après une inscription réussie, la
    // page doit naviguer vers /account-setup.
    testWidgets('SignupSuccess → navigue vers /account-setup', (tester) async {
      whenListen(
        cubit,
        Stream.fromIterable([const SignupSuccess()]),
        initialState: const SignupLoading(),
      );

      final router = GoRouter(
        initialLocation: AppRouter.signup,
        routes: [
          GoRoute(
            path: AppRouter.signup,
            builder: (_, __) => BlocProvider<SignupCubit>.value(
              value: cubit,
              child: const SignupPage(),
            ),
          ),
          GoRoute(
            path: AppRouter.accountSetup,
            builder: (_, __) =>
                const Scaffold(body: Text('account-setup page')),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();

      expect(find.text('account-setup page'), findsOneWidget);
    });

    testWidgets('SignupFailure → snackbar affiché avec le message',
        (tester) async {
      whenListen(
        cubit,
        Stream.fromIterable([
          const SignupFailure('E-mail déjà utilisé.'),
        ]),
        initialState: const SignupIdle(),
      );

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      expect(find.text('E-mail déjà utilisé.'), findsOneWidget);
    });
  });
}
