import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_practicien/features/login/login_page.dart';
import 'package:app_practicien/session/pro_auth_cubit.dart';

class _MockProAuthCubit extends MockCubit<AuthState> implements ProAuthCubit {}

void main() {
  group('LoginPage (praticien) — smoke', () {
    late _MockProAuthCubit cubit;

    setUp(() {
      cubit = _MockProAuthCubit();
      when(() => cubit.state).thenReturn(const AuthUnauthenticated());
    });

    testWidgets('s\'affiche sans erreur avec l\'état non authentifié',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<ProAuthCubit>.value(
            value: cubit,
            child: const LoginPage(),
          ),
        ),
      );

      expect(find.text('Se connecter'), findsOneWidget);
      expect(find.text('Nubia · Praticien'), findsNothing);
    });

    testWidgets('affiche un message d\'erreur si AuthUnauthenticated.message est renseigné',
        (tester) async {
      when(() => cubit.state)
          .thenReturn(const AuthUnauthenticated('Identifiants incorrects.'));

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<ProAuthCubit>.value(
            value: cubit,
            child: const LoginPage(),
          ),
        ),
      );

      expect(find.text('Identifiants incorrects.'), findsOneWidget);
    });
  });
}
