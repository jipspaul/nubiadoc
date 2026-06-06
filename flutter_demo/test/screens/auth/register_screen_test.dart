import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_demo/features/auth/bloc/auth_bloc.dart';
import 'package:flutter_demo/features/auth/bloc/auth_event.dart';
import 'package:flutter_demo/features/auth/bloc/auth_state.dart';
import 'package:flutter_demo/features/auth/register_screen.dart';
import 'package:flutter_demo/theme/nubia_theme.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

Widget _wrap(Widget child, AuthBloc bloc) {
  return MaterialApp(
    theme: NubiaTheme.light,
    home: BlocProvider<AuthBloc>.value(value: bloc, child: child),
  );
}

void main() {
  late MockAuthBloc mockBloc;

  setUp(() {
    mockBloc = MockAuthBloc();
    when(() => mockBloc.state).thenReturn(const AuthUnauthenticated());
  });

  group('RegisterScreen', () {
    testWidgets('renders without throwing', (tester) async {
      await tester.pumpWidget(_wrap(const RegisterScreen(), mockBloc));
      expect(find.byType(RegisterScreen), findsOneWidget);
    });

    testWidgets('shows email, password and CGU checkbox', (tester) async {
      await tester.pumpWidget(_wrap(const RegisterScreen(), mockBloc));
      expect(find.byKey(const Key('register_email')), findsOneWidget);
      expect(find.byKey(const Key('register_password')), findsOneWidget);
      expect(find.byKey(const Key('register_cgu_checkbox')), findsOneWidget);
    });

    testWidgets('shows submit button', (tester) async {
      await tester.pumpWidget(_wrap(const RegisterScreen(), mockBloc));
      expect(find.byKey(const Key('register_submit')), findsOneWidget);
    });

    testWidgets('shows email validation error on invalid email', (tester) async {
      await tester.pumpWidget(_wrap(const RegisterScreen(), mockBloc));
      await tester.enterText(
        find.byKey(const Key('register_email')),
        'not-an-email',
      );
      await tester.tap(find.byKey(const Key('register_submit')));
      await tester.pump();
      expect(find.text('E-mail invalide'), findsOneWidget);
    });

    testWidgets('shows password strength error when missing uppercase', (tester) async {
      await tester.pumpWidget(_wrap(const RegisterScreen(), mockBloc));
      await tester.enterText(
        find.byKey(const Key('register_password')),
        'nouppercase1',
      );
      await tester.tap(find.byKey(const Key('register_submit')));
      await tester.pump();
      expect(find.text('1 majuscule requise'), findsOneWidget);
    });

    testWidgets('shows password strength error when missing digit', (tester) async {
      await tester.pumpWidget(_wrap(const RegisterScreen(), mockBloc));
      await tester.enterText(
        find.byKey(const Key('register_password')),
        'NoDigitHere',
      );
      await tester.tap(find.byKey(const Key('register_submit')));
      await tester.pump();
      expect(find.text('1 chiffre requis'), findsOneWidget);
    });

    testWidgets('shows CGU version text', (tester) async {
      await tester.pumpWidget(_wrap(const RegisterScreen(), mockBloc));
      expect(
        find.textContaining("conditions générales d'utilisation"),
        findsOneWidget,
      );
    });
  });
}
