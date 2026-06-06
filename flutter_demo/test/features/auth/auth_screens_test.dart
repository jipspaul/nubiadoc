import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_demo/features/auth/bloc/auth_bloc.dart';
import 'package:flutter_demo/features/auth/bloc/auth_event.dart';
import 'package:flutter_demo/features/auth/bloc/auth_state.dart';
import 'package:flutter_demo/features/auth/login_screen.dart';
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

  group('LoginScreen', () {
    testWidgets('renders without throwing', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen(), mockBloc));
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('shows email and password fields', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen(), mockBloc));
      expect(find.byKey(const Key('login_email')), findsOneWidget);
      expect(find.byKey(const Key('login_password')), findsOneWidget);
    });

    testWidgets('shows submit button', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen(), mockBloc));
      expect(find.byKey(const Key('login_submit')), findsOneWidget);
    });
  });

  group('RegisterScreen', () {
    testWidgets('renders without throwing', (tester) async {
      await tester.pumpWidget(_wrap(const RegisterScreen(), mockBloc));
      expect(find.byType(RegisterScreen), findsOneWidget);
    });

    testWidgets('shows email, password and CGU fields', (tester) async {
      await tester.pumpWidget(_wrap(const RegisterScreen(), mockBloc));
      expect(find.byKey(const Key('register_email')), findsOneWidget);
      expect(find.byKey(const Key('register_password')), findsOneWidget);
      expect(find.byKey(const Key('register_cgu_checkbox')), findsOneWidget);
    });

    testWidgets('shows submit button', (tester) async {
      await tester.pumpWidget(_wrap(const RegisterScreen(), mockBloc));
      expect(find.byKey(const Key('register_submit')), findsOneWidget);
    });
  });
}
