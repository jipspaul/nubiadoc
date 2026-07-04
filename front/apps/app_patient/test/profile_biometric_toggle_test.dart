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
import 'package:app_patient/session/auth_cubit.dart';

class MockGetAccountUseCase extends Mock implements GetAccountUseCase {}

class MockUserSettingsRepository extends Mock
    implements UserSettingsRepository {}

class MockNotificationRepository extends Mock
    implements NotificationRepository {}

class MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

const _account = PatientAccount(
  id: 'acc-1',
  firstName: 'Marie',
  lastName: 'Curie',
  email: 'marie@example.com',
  phone: '0601020304',
);

const _prefs = NotificationPreferences.allEnabled();

Widget _wrap(ProfileBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: bloc),
          BlocProvider<AuthCubit>(create: (_) => MockAuthCubit()),
        ],
        child: const Scaffold(body: ProfilePage()),
      ),
    );

void main() {
  late MockGetAccountUseCase mockGetAccount;
  late MockUserSettingsRepository mockUserSettings;
  late MockNotificationRepository mockNotifRepo;

  setUp(() {
    mockGetAccount = MockGetAccountUseCase();
    mockUserSettings = MockUserSettingsRepository();
    mockNotifRepo = MockNotificationRepository();
    when(() => mockGetAccount()).thenAnswer((_) async => const Right(_account));
    when(() => mockUserSettings.setBiometricEnabled(any()))
        .thenAnswer((_) async {});
    when(() => mockNotifRepo.getPreferences())
        .thenAnswer((_) async => const Right(_prefs));
  });

  group('ProfilePage — biometric toggle', () {
    testWidgets(
      'tap toggle ON → setBiometricEnabled(true) appelé',
      (tester) async {
        when(() => mockUserSettings.getBiometricEnabled())
            .thenAnswer((_) async => false);

        final bloc = ProfileBloc(
          getAccount: mockGetAccount,
          userSettings: mockUserSettings,
          notificationRepo: mockNotifRepo,
        );
        bloc.add(const ProfileLoadRequested());

        await tester.pumpWidget(_wrap(bloc));
        await tester.pumpAndSettle();

        await tester.dragUntilVisible(
          find.byKey(const Key('biometric_toggle')),
          find.byKey(const Key('profile_content')),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('biometric_toggle')));
        await tester.pumpAndSettle();

        verify(() => mockUserSettings.setBiometricEnabled(true)).called(1);
      },
    );

    testWidgets(
      'tap toggle OFF → setBiometricEnabled(false) appelé',
      (tester) async {
        when(() => mockUserSettings.getBiometricEnabled())
            .thenAnswer((_) async => true);

        final bloc = ProfileBloc(
          getAccount: mockGetAccount,
          userSettings: mockUserSettings,
          notificationRepo: mockNotifRepo,
        );
        bloc.add(const ProfileLoadRequested());

        await tester.pumpWidget(_wrap(bloc));
        await tester.pumpAndSettle();

        await tester.dragUntilVisible(
          find.byKey(const Key('biometric_toggle')),
          find.byKey(const Key('profile_content')),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('biometric_toggle')));
        await tester.pumpAndSettle();

        verify(() => mockUserSettings.setBiometricEnabled(false)).called(1);
      },
    );
  });
}
