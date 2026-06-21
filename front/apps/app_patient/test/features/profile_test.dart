import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/profile/profile_bloc.dart';
import 'package:app_patient/features/profile/profile_event.dart';
import 'package:app_patient/features/profile/profile_page.dart';
import 'package:app_patient/features/profile/profile_state.dart';
import 'package:app_patient/session/auth_cubit.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetAccountUseCase extends Mock implements GetAccountUseCase {}

class MockUserSettingsRepository extends Mock
    implements UserSettingsRepository {}

class MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _account = PatientAccount(
  id: 'acc-1',
  firstName: 'Marie',
  lastName: 'Curie',
  email: 'marie@example.com',
  phone: '0601020304',
);

Widget _wrap(ProfileBloc bloc) => MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: bloc),
          BlocProvider<AuthCubit>(create: (_) => MockAuthCubit()),
        ],
        child: const Scaffold(body: ProfilePage()),
      ),
    );

ProfileBloc _makeBloc(
  MockGetAccountUseCase getAccount,
  MockUserSettingsRepository userSettings,
) =>
    ProfileBloc(getAccount: getAccount, userSettings: userSettings);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockGetAccountUseCase mockGetAccount;
  late MockUserSettingsRepository mockUserSettings;

  setUp(() {
    mockGetAccount = MockGetAccountUseCase();
    mockUserSettings = MockUserSettingsRepository();
    when(() => mockUserSettings.getBiometricEnabled())
        .thenAnswer((_) async => false);
  });

  group('ProfilePage', () {
    testWidgets('affiche le skeleton loader en état initial', (tester) async {
      final bloc = _makeBloc(mockGetAccount, mockUserSettings);

      await tester.pumpWidget(_wrap(bloc));

      expect(find.byType(NubiaSkeletonLoader), findsWidgets);
    });

    testWidgets('affiche les informations du compte en état loaded',
        (tester) async {
      when(() => mockGetAccount())
          .thenAnswer((_) async => const Right(_account));

      final bloc = _makeBloc(mockGetAccount, mockUserSettings);
      bloc.add(const ProfileLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile_content')), findsOneWidget);
      expect(find.text('Marie Curie'), findsOneWidget);
      expect(find.text('marie@example.com'), findsAtLeastNWidgets(1));
    });

    testWidgets('affiche un message d\'erreur en état error', (tester) async {
      when(() => mockGetAccount()).thenAnswer(
        (_) async => const Left(NetworkFailure('Erreur réseau.')),
      );

      final bloc = _makeBloc(mockGetAccount, mockUserSettings);
      bloc.add(const ProfileLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.text('Erreur réseau.'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });
  });

  group('ProfileBloc', () {
    blocTest<ProfileBloc, ProfileState>(
      'émet [Loading, Loaded] quand getAccount réussit',
      build: () {
        when(() => mockGetAccount())
            .thenAnswer((_) async => const Right(_account));
        return _makeBloc(mockGetAccount, mockUserSettings);
      },
      act: (bloc) => bloc.add(const ProfileLoadRequested()),
      expect: () => [
        const ProfileLoading(),
        isA<ProfileLoaded>()
            .having((s) => s.account.email, 'email', 'marie@example.com'),
      ],
    );

    blocTest<ProfileBloc, ProfileState>(
      'émet [Loading, Error] quand getAccount échoue',
      build: () {
        when(() => mockGetAccount()).thenAnswer(
          (_) async => const Left(NetworkFailure('Erreur réseau.')),
        );
        return _makeBloc(mockGetAccount, mockUserSettings);
      },
      act: (bloc) => bloc.add(const ProfileLoadRequested()),
      expect: () => [
        const ProfileLoading(),
        isA<ProfileError>()
            .having((s) => s.message, 'message', 'Erreur réseau.'),
      ],
    );
  });
}
