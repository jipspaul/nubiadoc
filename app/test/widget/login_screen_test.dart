import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_bloc.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_event.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_state.dart';
import 'package:nubia_patient/presentation/features/auth/pages/login_screen.dart';
import 'package:nubia_patient/presentation/widgets/nubia_button.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

Widget _wrap(Widget child, AuthBloc bloc) {
  return MaterialApp(
    home: BlocProvider<AuthBloc>.value(
      value: bloc,
      child: child,
    ),
  );
}

void main() {
  late MockAuthBloc authBloc;

  setUp(() {
    authBloc = MockAuthBloc();
    when(() => authBloc.state).thenReturn(const AuthInitial());
  });

  testWidgets('LoginScreen renders email field, password field and submit button',
      (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen(), authBloc));

    expect(find.byKey(const Key('login_email_field')), findsOneWidget);
    expect(find.byKey(const Key('login_password_field')), findsOneWidget);
    expect(find.byKey(const Key('login_submit_button')), findsOneWidget);
  });

  testWidgets('LoginScreen submit button disabled when fields are empty',
      (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen(), authBloc));

    final button = tester.widget<NubiaButton>(
      find.byKey(const Key('login_submit_button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('LoginScreen submit button disabled when only email filled',
      (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen(), authBloc));

    await tester.enterText(
        find.byKey(const Key('login_email_field')), 'alice@example.com');
    await tester.pump();

    final button = tester.widget<NubiaButton>(
      find.byKey(const Key('login_submit_button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('LoginScreen submit button disabled when only password filled',
      (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen(), authBloc));

    await tester.enterText(
        find.byKey(const Key('login_password_field')), 'secret');
    await tester.pump();

    final button = tester.widget<NubiaButton>(
      find.byKey(const Key('login_submit_button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('LoginScreen submit button enabled when both fields filled',
      (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen(), authBloc));

    await tester.enterText(
        find.byKey(const Key('login_email_field')), 'alice@example.com');
    await tester.enterText(
        find.byKey(const Key('login_password_field')), 'secret');
    await tester.pump();

    final button = tester.widget<NubiaButton>(
      find.byKey(const Key('login_submit_button')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('LoginScreen shows loader when AuthLoading', (tester) async {
    when(() => authBloc.state).thenReturn(const AuthLoading());

    await tester.pumpWidget(_wrap(const LoginScreen(), authBloc));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('LoginScreen submit button disabled when AuthLoading',
      (tester) async {
    when(() => authBloc.state).thenReturn(const AuthLoading());

    await tester.pumpWidget(_wrap(const LoginScreen(), authBloc));

    final button = tester.widget<NubiaButton>(
      find.byKey(const Key('login_submit_button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('LoginScreen shows error snackbar on AuthFailure', (tester) async {
    whenListen(
      authBloc,
      Stream.fromIterable([
        const AuthFailure('Identifiants incorrects.'),
      ]),
      initialState: const AuthInitial(),
    );

    await tester.pumpWidget(_wrap(const LoginScreen(), authBloc));
    await tester.pump();

    expect(find.text('Identifiants incorrects.'), findsOneWidget);
  });
}
