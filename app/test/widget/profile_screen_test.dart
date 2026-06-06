import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_bloc.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_event.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_state.dart';
import 'package:nubia_patient/presentation/features/profile/bloc/profile_bloc.dart';
import 'package:nubia_patient/presentation/features/profile/bloc/profile_event.dart';
import 'package:nubia_patient/presentation/features/profile/bloc/profile_state.dart';
import 'package:nubia_patient/presentation/features/profile/widgets/profile_menu_tile.dart';

class MockProfileBloc extends MockBloc<ProfileEvent, ProfileState>
    implements ProfileBloc {}

class MockAuthBloc extends MockBloc<AuthEvent, AuthState>
    implements AuthBloc {}

const _account = PatientAccount(
  id: 'u1',
  firstName: 'Alice',
  lastName: 'Martin',
  email: 'alice@example.com',
  phone: '0612345678',
);

Widget _wrap({
  required ProfileBloc profileBloc,
  required AuthBloc authBloc,
}) {
  return MaterialApp(
    home: MultiBlocProvider(
      providers: [
        BlocProvider<ProfileBloc>.value(value: profileBloc),
        BlocProvider<AuthBloc>.value(value: authBloc),
      ],
      child: Scaffold(
        body: BlocBuilder<ProfileBloc, ProfileState>(
          builder: (context, state) {
            if (state is ProfileLoading || state is ProfileInitial) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is ProfileError) {
              return Center(child: Text(state.message));
            }
            if (state is ProfileLoaded) {
              return ListView(
                children: [
                  Text(state.account.displayName),
                  Text(state.account.email),
                  const ProfileMenuTile(
                    icon: Icons.health_and_safety_outlined,
                    title: 'Couverture santé',
                    onTap: _noop,
                  ),
                  const ProfileMenuTile(
                    icon: Icons.people_outline,
                    title: 'Mes proches',
                    onTap: _noop,
                  ),
                  const ProfileMenuTile(
                    icon: Icons.local_hospital_outlined,
                    title: 'Infos cabinet',
                    onTap: _noop,
                  ),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
}

void _noop() {}

void main() {
  late MockProfileBloc profileBloc;
  late MockAuthBloc authBloc;

  setUp(() {
    profileBloc = MockProfileBloc();
    authBloc = MockAuthBloc();
  });

  tearDown(() {
    profileBloc.close();
    authBloc.close();
  });

  testWidgets('affiche un indicateur de chargement en état Loading',
      (tester) async {
    when(() => profileBloc.state).thenReturn(const ProfileLoading());

    await tester.pumpWidget(_wrap(
      profileBloc: profileBloc,
      authBloc: authBloc,
    ));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('affiche les infos utilisateur en état Loaded', (tester) async {
    when(() => profileBloc.state).thenReturn(const ProfileLoaded(_account));

    await tester.pumpWidget(_wrap(
      profileBloc: profileBloc,
      authBloc: authBloc,
    ));

    expect(find.text('Alice Martin'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('Couverture santé'), findsOneWidget);
    expect(find.text('Mes proches'), findsOneWidget);
    expect(find.text('Infos cabinet'), findsOneWidget);
  });

  testWidgets('affiche un message d\'erreur en état Error', (tester) async {
    when(() => profileBloc.state)
        .thenReturn(const ProfileError('Erreur réseau.'));

    await tester.pumpWidget(_wrap(
      profileBloc: profileBloc,
      authBloc: authBloc,
    ));

    expect(find.text('Erreur réseau.'), findsOneWidget);
  });
}
