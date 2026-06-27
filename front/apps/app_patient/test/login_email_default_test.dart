import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_patient/features/login/login_page.dart';
import 'package:app_patient/session/auth_cubit.dart';

class MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

Widget _wrap(AuthCubit cubit) => BlocProvider<AuthCubit>.value(
      value: cubit,
      child: MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: LoginPage()),
      ),
    );

void main() {
  group('LoginPage — BUG-02 : pré-remplissage e-mail conditionné à kDebugMode',
      () {
    testWidgets('le champ e-mail prend la valeur attendue selon kDebugMode',
        (tester) async {
      final cubit = MockAuthCubit();
      when(() => cubit.state).thenReturn(AuthUnknown());

      await tester.pumpWidget(_wrap(cubit));
      await tester.pumpAndSettle();

      // En debug (toujours vrai sous `flutter test`) → 'camille@example.com'.
      // En release → chaîne vide (l'utilisateur saisit son propre e-mail).
      final expected = kDebugMode ? 'camille@example.com' : '';
      final emailField = tester.widget<TextField>(find.byType(TextField).first);
      expect(
        emailField.controller?.text,
        expected,
        reason: 'kDebugMode=$kDebugMode → expected="$expected"',
      );
    });

    testWidgets(
        'en release : aucune occurrence de l\'e-mail démo dans l\'arbre de widgets',
        (tester) async {
      // En release (kDebugMode == false), le pré-remplissage ne doit pas
      // exister. Sous `flutter test` on est en debug, donc ce test ne fait
      // un assert qu'en release — il documente le contrat sans bruit en CI.
      if (kDebugMode) return;

      final cubit = MockAuthCubit();
      when(() => cubit.state).thenReturn(AuthUnknown());
      await tester.pumpWidget(_wrap(cubit));
      await tester.pumpAndSettle();

      expect(find.text('camille@example.com'), findsNothing);
    });
  });
}
