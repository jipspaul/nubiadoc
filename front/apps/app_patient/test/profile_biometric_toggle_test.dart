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

class MockUpdateAccountUseCase extends Mock implements UpdateAccountUseCase {}

class MockUserSettingsRepository extends Mock
    implements UserSettingsRepository {}

class MockNotificationRepository extends Mock
    implements NotificationRepository {}

class MockGetPendingQuotesUseCase extends Mock
    implements GetPendingQuotesUseCase {}

class MockGetCoverageUseCase extends Mock implements GetCoverageUseCase {}

class MockGetReferringDoctorUseCase extends Mock
    implements GetReferringDoctorUseCase {}

class MockListDependentsUseCase extends Mock
    implements ListDependentsUseCase {}

class MockListConsentsUseCase extends Mock implements ListConsentsUseCase {}

class MockListImplantPassportUseCase extends Mock
    implements ListImplantPassportUseCase {}

class MockGetMyPharmacyUseCase extends Mock implements GetMyPharmacyUseCase {}

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
  late MockUpdateAccountUseCase mockUpdateAccount;
  late MockUserSettingsRepository mockUserSettings;
  late MockNotificationRepository mockNotifRepo;
  late MockGetPendingQuotesUseCase mockGetPendingQuotes;
  late MockGetCoverageUseCase mockGetCoverage;
  late MockGetReferringDoctorUseCase mockGetReferringDoctor;
  late MockListDependentsUseCase mockListDependents;
  late MockListConsentsUseCase mockListConsents;
  late MockListImplantPassportUseCase mockListImplants;
  late MockGetMyPharmacyUseCase mockGetMyPharmacy;

  setUp(() {
    mockGetAccount = MockGetAccountUseCase();
    mockUpdateAccount = MockUpdateAccountUseCase();
    mockUserSettings = MockUserSettingsRepository();
    mockNotifRepo = MockNotificationRepository();
    mockGetPendingQuotes = MockGetPendingQuotesUseCase();
    mockGetCoverage = MockGetCoverageUseCase();
    mockGetReferringDoctor = MockGetReferringDoctorUseCase();
    mockListDependents = MockListDependentsUseCase();
    mockListConsents = MockListConsentsUseCase();
    mockListImplants = MockListImplantPassportUseCase();
    mockGetMyPharmacy = MockGetMyPharmacyUseCase();
    when(() => mockGetAccount()).thenAnswer((_) async => const Right(_account));
    when(() => mockUserSettings.setBiometricEnabled(any()))
        .thenAnswer((_) async {});
    when(() => mockNotifRepo.getPreferences())
        .thenAnswer((_) async => const Right(_prefs));
    when(() => mockGetPendingQuotes()).thenAnswer((_) async => const Right([]));
    when(() => mockGetCoverage()).thenAnswer((_) async => const Right(
        HealthCoverage(regime: HealthInsuranceRegime.regimeGeneral)));
    when(() => mockGetReferringDoctor())
        .thenAnswer((_) async => const Right(null));
    when(() => mockListDependents()).thenAnswer((_) async => const Right([]));
    when(() => mockListConsents()).thenAnswer((_) async => const Right([]));
    when(() => mockListImplants()).thenAnswer((_) async => const Right([]));
    when(() => mockGetMyPharmacy()).thenAnswer((_) async => const Right(null));
  });

  group('ProfilePage — biometric toggle', () {
    testWidgets(
      'tap toggle ON → setBiometricEnabled(true) appelé',
      (tester) async {
        when(() => mockUserSettings.getBiometricEnabled())
            .thenAnswer((_) async => false);

        final bloc = ProfileBloc(
          getAccount: mockGetAccount,
          updateAccount: mockUpdateAccount,
          userSettings: mockUserSettings,
          notificationRepo: mockNotifRepo,
          getPendingQuotes: mockGetPendingQuotes,
          getCoverage: mockGetCoverage,
          getReferringDoctor: mockGetReferringDoctor,
          listDependents: mockListDependents,
          listConsents: mockListConsents,
          listImplants: mockListImplants,
          getMyPharmacy: mockGetMyPharmacy,
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
          updateAccount: mockUpdateAccount,
          userSettings: mockUserSettings,
          notificationRepo: mockNotifRepo,
          getPendingQuotes: mockGetPendingQuotes,
          getCoverage: mockGetCoverage,
          getReferringDoctor: mockGetReferringDoctor,
          listDependents: mockListDependents,
          listConsents: mockListConsents,
          listImplants: mockListImplants,
          getMyPharmacy: mockGetMyPharmacy,
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
