import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_secretariat/features/login/login_page.dart';
import 'package:app_secretariat/session/pro_auth_cubit.dart';

class _MockProAuthCubit extends MockCubit<AuthState> implements ProAuthCubit {}

Widget _wrap(Widget child, ProAuthCubit cubit) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<ProAuthCubit>.value(
        value: cubit,
        child: child,
      ),
    );

void main() {
  group('LoginPage — encart invitation', () {
    late _MockProAuthCubit cubit;

    setUp(() {
      cubit = _MockProAuthCubit();
      when(() => cubit.state).thenReturn(const AuthUnauthenticated());
    });

    testWidgets('affiche l\'encart info invitation', (tester) async {
      await tester.pumpWidget(_wrap(const LoginPage(), cubit));

      expect(
        find.byKey(const Key('login_invitation_help_card')),
        findsOneWidget,
      );
    });

    testWidgets('affiche le titre "Pas de compte ?"', (tester) async {
      await tester.pumpWidget(_wrap(const LoginPage(), cubit));

      expect(find.text('Pas de compte ?'), findsOneWidget);
    });

    testWidgets('affiche le texte d\'aide exact', (tester) async {
      await tester.pumpWidget(_wrap(const LoginPage(), cubit));

      expect(
        find.textContaining(
          "Le compte secrétariat se crée sur invitation par le praticien.",
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          "Si vous avez reçu un lien d'invitation par email, ouvrez-le pour finaliser votre inscription.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('affiche l\'icône info_outline', (tester) async {
      await tester.pumpWidget(_wrap(const LoginPage(), cubit));

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });
  });
}
