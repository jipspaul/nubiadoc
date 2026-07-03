import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_patient/features/forgot_password/forgot_password_cubit.dart';
import 'package:app_patient/features/forgot_password/forgot_password_page.dart';

class MockForgotPasswordCubit extends MockCubit<ForgotPasswordState>
    implements ForgotPasswordCubit {}

Widget _wrap(ForgotPasswordCubit cubit) => BlocProvider<ForgotPasswordCubit>.value(
      value: cubit,
      child: MaterialApp(
        theme: NubiaTheme.light,
        home: const ForgotPasswordPage(),
      ),
    );

FilledButton _submit(WidgetTester tester) => tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const Key('forgot_password_submit')),
        matching: find.byType(FilledButton),
      ),
    );

void main() {
  late MockForgotPasswordCubit cubit;

  setUp(() {
    cubit = MockForgotPasswordCubit();
    when(() => cubit.state).thenReturn(const ForgotPasswordIdle());
  });

  group('ForgotPasswordPage', () {
    testWidgets('e-mail vide → bouton désactivé', (tester) async {
      await tester.pumpWidget(_wrap(cubit));

      expect(_submit(tester).onPressed, isNull);
    });

    testWidgets('e-mail invalide → bouton désactivé + erreur inline',
        (tester) async {
      await tester.pumpWidget(_wrap(cubit));

      await tester.enterText(find.byType(TextField), 'pas-un-email');
      await tester.pump();

      expect(_submit(tester).onPressed, isNull);
      expect(find.text('E-mail invalide.'), findsOneWidget);
    });

    testWidgets('e-mail valide → bouton activé, submit appelle le cubit',
        (tester) async {
      when(() => cubit.submit(any())).thenAnswer((_) async {});

      await tester.pumpWidget(_wrap(cubit));

      await tester.enterText(find.byType(TextField), 'marc@exemple.fr');
      await tester.pump();

      expect(_submit(tester).onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('forgot_password_submit')));
      verify(() => cubit.submit('marc@exemple.fr')).called(1);
    });

    testWidgets('ForgotPasswordSent → message de confirmation', (tester) async {
      when(() => cubit.state).thenReturn(const ForgotPasswordSent());

      await tester.pumpWidget(_wrap(cubit));

      expect(
          find.byKey(const Key('forgot_password_confirmation')), findsOneWidget);
      expect(find.byKey(const Key('forgot_password_submit')), findsNothing);
    });

    testWidgets('ForgotPasswordFailure → message affiché', (tester) async {
      when(() => cubit.state).thenReturn(const ForgotPasswordFailure(
          'Trop de tentatives de connexion. Patientez une minute puis réessayez.'));

      await tester.pumpWidget(_wrap(cubit));

      expect(
        find.text(
            'Trop de tentatives de connexion. Patientez une minute puis réessayez.'),
        findsOneWidget,
      );
    });
  });
}
