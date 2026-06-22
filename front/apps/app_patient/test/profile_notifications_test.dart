import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
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

const _prefs = NotificationPreferences(
  pushEnabled: true,
  emailEnabled: true,
  smsEnabled: true,
  appointments: true,
  documents: true,
  messages: true,
  payments: true,
  prevention: true,
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

void main() {
  late MockGetAccountUseCase mockGetAccount;
  late MockUserSettingsRepository mockUserSettings;
  late MockNotificationRepository mockNotifRepo;

  setUp(() {
    mockGetAccount = MockGetAccountUseCase();
    mockUserSettings = MockUserSettingsRepository();
    mockNotifRepo = MockNotificationRepository();
    when(() => mockGetAccount()).thenAnswer((_) async => const Right(_account));
    when(() => mockUserSettings.getBiometricEnabled())
        .thenAnswer((_) async => false);
    when(() => mockNotifRepo.updatePreferences(any()))
        .thenAnswer((_) async => const Right(null));
  });

  ProfileBloc makeBloc() => ProfileBloc(
        getAccount: mockGetAccount,
        userSettings: mockUserSettings,
        notificationRepo: mockNotifRepo,
      );

  group('ProfilePage — Notifications RDV', () {
    testWidgets('état initial : lit les préférences depuis le repo',
        (tester) async {
      when(() => mockNotifRepo.getPreferences())
          .thenAnswer((_) async => const Right(_prefs));

      final bloc = makeBloc()..add(const ProfileLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      verify(() => mockNotifRepo.getPreferences()).called(1);
      expect(find.byKey(const Key('email_rdv_toggle')), findsOneWidget);
      expect(find.byKey(const Key('push_rdv_toggle')), findsOneWidget);
    });

    testWidgets('toggle email → updatePreferences appelé avec emailEnabled=false',
        (tester) async {
      when(() => mockNotifRepo.getPreferences())
          .thenAnswer((_) async => const Right(_prefs));

      final bloc = makeBloc()..add(const ProfileLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('email_rdv_toggle')));
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockNotifRepo.updatePreferences(captureAny()),
      ).captured;
      final updated = captured.last as NotificationPreferences;
      expect(updated.emailEnabled, isFalse);
    });

    testWidgets('toggle push → updatePreferences appelé avec pushEnabled=false',
        (tester) async {
      when(() => mockNotifRepo.getPreferences())
          .thenAnswer((_) async => const Right(_prefs));

      final bloc = makeBloc()..add(const ProfileLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('push_rdv_toggle')));
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockNotifRepo.updatePreferences(captureAny()),
      ).captured;
      final updated = captured.last as NotificationPreferences;
      expect(updated.pushEnabled, isFalse);
    });
  });
}
