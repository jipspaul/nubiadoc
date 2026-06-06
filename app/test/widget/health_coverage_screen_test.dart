import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';
import 'package:nubia_patient/presentation/features/profile/bloc/profile_bloc.dart';
import 'package:nubia_patient/presentation/features/profile/bloc/profile_event.dart';
import 'package:nubia_patient/presentation/features/profile/bloc/profile_state.dart';
import 'package:nubia_patient/presentation/features/profile/pages/health_coverage_screen.dart';

class MockProfileBloc extends MockBloc<ProfileEvent, ProfileState>
    implements ProfileBloc {}

const _coverage = HealthCoverage(
  regime: HealthInsuranceRegime.regimeGeneral,
  insuranceName: 'MGEN',
  memberNumber: '123456789',
  thirdPartyPayment: true,
);

const _account = PatientAccount(
  id: 'u1',
  firstName: 'Alice',
  lastName: 'Martin',
  email: 'alice@example.com',
  coverage: _coverage,
);

Widget _wrap(ProfileBloc bloc) {
  return MaterialApp(
    home: BlocProvider<ProfileBloc>.value(
      value: bloc,
      child: const HealthCoverageScreen(),
    ),
  );
}

void main() {
  late MockProfileBloc bloc;

  setUp(() => bloc = MockProfileBloc());
  tearDown(() => bloc.close());

  testWidgets('affiche un indicateur de chargement en état Loading',
      (tester) async {
    when(() => bloc.state).thenReturn(const ProfileLoading());

    await tester.pumpWidget(_wrap(bloc));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('affiche les champs de couverture santé en état Loaded',
      (tester) async {
    when(() => bloc.state).thenReturn(const ProfileLoaded(_account));

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('Régime général'), findsOneWidget);
    expect(find.text('MGEN'), findsOneWidget);
    expect(find.text('123456789'), findsOneWidget);
    expect(find.text('Oui'), findsOneWidget);
  });

  testWidgets('affiche un message vide quand aucune couverture', (tester) async {
    const accountNoCoverage = PatientAccount(
      id: 'u2',
      firstName: 'Bob',
      lastName: 'Dupont',
      email: 'bob@example.com',
    );
    when(() => bloc.state).thenReturn(const ProfileLoaded(accountNoCoverage));

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('Aucune couverture santé renseignée'), findsOneWidget);
  });
}
