import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_bloc.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_event.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_state.dart';
import 'package:nubia_patient/presentation/features/auth/pages/register_screen.dart';

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

  testWidgets('RegisterScreen renders email, password, invite token fields and submit button',
      (tester) async {
    await tester.pumpWidget(_wrap(const RegisterScreen(), authBloc));

    expect(find.byKey(const Key('register_email_field')), findsOneWidget);
    expect(find.byKey(const Key('register_password_field')), findsOneWidget);
    expect(find.byKey(const Key('register_invite_token_field')), findsOneWidget);
    expect(find.byKey(const Key('register_submit_button')), findsOneWidget);
  });

  testWidgets('RegisterScreen shows validation error for invalid email',
      (tester) async {
    await tester.pumpWidget(_wrap(const RegisterScreen(), authBloc));

    // Enter an invalid email and submit
    await tester.enterText(
        find.byKey(const Key('register_email_field')), 'not-an-email');
    await tester.enterText(
        find.byKey(const Key('register_password_field')), 'password123');
    await tester.enterText(
        find.byKey(const Key('register_invite_token_field')), 'INVITE42');
    await tester.tap(find.byKey(const Key('register_submit_button')));
    await tester.pump();

    expect(find.text('Adresse e-mail invalide.'), findsOneWidget);
  });
}
