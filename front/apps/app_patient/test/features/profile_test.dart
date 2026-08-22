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

class MockUpdateAccountUseCase extends Mock implements UpdateAccountUseCase {}

class MockUserSettingsRepository extends Mock
    implements UserSettingsRepository {}

class MockNotificationRepository extends Mock
    implements NotificationRepository {}

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
      theme: NubiaTheme.light,
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
  MockNotificationRepository notifRepo, [
  MockUpdateAccountUseCase? updateAccount,
]) =>
    ProfileBloc(
        getAccount: getAccount,
        updateAccount: updateAccount ?? MockUpdateAccountUseCase(),
        userSettings: userSettings,
        notificationRepo: notifRepo);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const _prefs = NotificationPreferences.allEnabled();

void main() {
  setUpAll(() {
    registerFallbackValue(const NotificationPreferences.allEnabled());
  });

  late MockGetAccountUseCase mockGetAccount;
  late MockUserSettingsRepository mockUserSettings;
  late MockNotificationRepository mockNotifRepo;

  setUp(() {
    mockGetAccount = MockGetAccountUseCase();
    mockUserSettings = MockUserSettingsRepository();
    mockNotifRepo = MockNotificationRepository();
    when(() => mockUserSettings.getBiometricEnabled())
        .thenAnswer((_) async => false);
    when(() => mockNotifRepo.getPreferences())
        .thenAnswer((_) async => const Right(_prefs));
  });

  group('ProfilePage', () {
    testWidgets('affiche un squelette de chargement en état initial',
        (tester) async {
      final bloc = _makeBloc(mockGetAccount, mockUserSettings, mockNotifRepo);

      await tester.pumpWidget(_wrap(bloc));

      expect(find.byKey(const Key('profile_loading')), findsOneWidget);
    });

    testWidgets('affiche les informations du compte en état loaded',
        (tester) async {
      when(() => mockGetAccount())
          .thenAnswer((_) async => const Right(_account));

      final bloc = _makeBloc(mockGetAccount, mockUserSettings, mockNotifRepo);
      bloc.add(const ProfileLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile_content')), findsOneWidget);
      expect(find.text('Marie Curie'), findsOneWidget);
      expect(find.text('marie@example.com'), findsAtLeastNWidgets(1));
    });

    testWidgets(
        'Informations personnelles : email en texte simple (#4544 — '
        'non modifiable, plus de faux champ de saisie désactivé)',
        (tester) async {
      when(() => mockGetAccount())
          .thenAnswer((_) async => const Right(_account));

      final bloc = _makeBloc(mockGetAccount, mockUserSettings, mockNotifRepo);
      bloc.add(const ProfileLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile_email_value')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('profile_email_value'))).data,
        'marie@example.com',
      );
      expect(
        find.ancestor(
          of: find.byKey(const Key('profile_email_value')),
          matching: find.byType(TextField),
        ),
        findsNothing,
      );
    });

    testWidgets(
        'Informations personnelles : tap crayon téléphone → dialog pré-rempli '
        '→ Enregistrer → PhoneUpdateRequested dispatché (#4544)',
        (tester) async {
      when(() => mockGetAccount())
          .thenAnswer((_) async => const Right(_account));
      final mockUpdateAccount = MockUpdateAccountUseCase();
      when(() => mockUpdateAccount(phone: any(named: 'phone'))).thenAnswer(
        (_) async => const Right(PatientAccount(
          id: 'acc-1',
          firstName: 'Marie',
          lastName: 'Curie',
          email: 'marie@example.com',
          phone: '+33698765432',
        )),
      );

      final bloc = _makeBloc(
          mockGetAccount, mockUserSettings, mockNotifRepo, mockUpdateAccount);
      bloc.add(const ProfileLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.text('0601020304'), findsOneWidget);

      await tester.tap(find.byKey(const Key('edit_phone_button')));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byKey(const Key('edit_phone_field')),
      );
      expect(field.controller?.text, '0601020304');

      await tester.enterText(
        find.byKey(const Key('edit_phone_field')),
        '+33698765432',
      );
      await tester.tap(find.byKey(const Key('save_phone_button')));
      await tester.pumpAndSettle();

      verify(() => mockUpdateAccount(phone: '+33698765432')).called(1);
      expect(find.text('+33698765432'), findsOneWidget);
    });

    testWidgets('expose un accès visible aux devis & paiements (#3351)',
        (tester) async {
      when(() => mockGetAccount())
          .thenAnswer((_) async => const Right(_account));

      final bloc = _makeBloc(mockGetAccount, mockUserSettings, mockNotifRepo);
      bloc.add(const ProfileLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('tile_financial')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('tile_financial')), findsOneWidget);
      expect(find.text('Mes devis & paiements'), findsOneWidget);
    });

    testWidgets('affiche un message d\'erreur en état error', (tester) async {
      when(() => mockGetAccount()).thenAnswer(
        (_) async => const Left(NetworkFailure('Erreur réseau.')),
      );

      final bloc = _makeBloc(mockGetAccount, mockUserSettings, mockNotifRepo);
      bloc.add(const ProfileLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.text('Erreur réseau.'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets(
        'affiche le contenu précédent et un snackbar en état ProfileToggleFailed',
        (tester) async {
      final bloc = _makeBloc(mockGetAccount, mockUserSettings, mockNotifRepo);
      const loaded =
          ProfileLoaded(_account, biometricEnabled: false, notifPrefs: _prefs);
      final failed = ProfileToggleFailed(loaded, 'Erreur biométrie');

      await tester.pumpWidget(_wrap(bloc));
      bloc.emit(failed);
      await tester.pump();

      expect(find.byKey(const Key('profile_content')), findsOneWidget);
      expect(find.text('Erreur biométrie'), findsOneWidget);
    });
  });

  group('ProfileBloc', () {
    blocTest<ProfileBloc, ProfileState>(
      'émet [Loading, Loaded] quand getAccount réussit',
      build: () {
        when(() => mockGetAccount())
            .thenAnswer((_) async => const Right(_account));
        return _makeBloc(mockGetAccount, mockUserSettings, mockNotifRepo);
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
        return _makeBloc(mockGetAccount, mockUserSettings, mockNotifRepo);
      },
      act: (bloc) => bloc.add(const ProfileLoadRequested()),
      expect: () => [
        const ProfileLoading(),
        isA<ProfileError>()
            .having((s) => s.message, 'message', 'Erreur réseau.'),
      ],
    );

    blocTest<ProfileBloc, ProfileState>(
      'BiometricToggleRequested : émet [Optimistic, ToggleFailed] quand setBiometricEnabled throw',
      build: () {
        when(() => mockUserSettings.setBiometricEnabled(any()))
            .thenThrow(Exception('Biometric save failed'));
        return _makeBloc(mockGetAccount, mockUserSettings, mockNotifRepo);
      },
      seed: () => const ProfileLoaded(_account,
          biometricEnabled: false, notifPrefs: _prefs),
      act: (bloc) => bloc.add(const BiometricToggleRequested(enabled: true)),
      expect: () => [
        isA<ProfileLoaded>()
            .having((s) => s.biometricEnabled, 'biometricEnabled', true),
        isA<ProfileToggleFailed>()
            .having((s) => s.previousState.biometricEnabled,
                'previousState.biometricEnabled', false)
            .having((s) => s.message, 'message', isNotEmpty),
      ],
    );

    blocTest<ProfileBloc, ProfileState>(
      'ToggleEmailRdv : émet [Optimistic, ToggleFailed] quand updatePreferences throw',
      build: () {
        when(() => mockNotifRepo.updatePreferences(any()))
            .thenThrow(Exception('Network error'));
        return _makeBloc(mockGetAccount, mockUserSettings, mockNotifRepo);
      },
      seed: () => const ProfileLoaded(_account,
          biometricEnabled: false, notifPrefs: _prefs),
      act: (bloc) => bloc.add(const ToggleEmailRdv(enabled: false)),
      expect: () => [
        isA<ProfileLoaded>()
            .having((s) => s.notifPrefs?.emailEnabled, 'emailEnabled', false),
        isA<ProfileToggleFailed>().having(
            (s) => s.previousState.notifPrefs?.emailEnabled,
            'previousState.emailEnabled',
            true),
      ],
    );

    blocTest<ProfileBloc, ProfileState>(
      'TogglePushRdv : émet [Optimistic, ToggleFailed] quand updatePreferences throw',
      build: () {
        when(() => mockNotifRepo.updatePreferences(any()))
            .thenThrow(Exception('Network error'));
        return _makeBloc(mockGetAccount, mockUserSettings, mockNotifRepo);
      },
      seed: () => const ProfileLoaded(_account,
          biometricEnabled: false, notifPrefs: _prefs),
      act: (bloc) => bloc.add(const TogglePushRdv(enabled: false)),
      expect: () => [
        isA<ProfileLoaded>()
            .having((s) => s.notifPrefs?.pushEnabled, 'pushEnabled', false),
        isA<ProfileToggleFailed>().having(
            (s) => s.previousState.notifPrefs?.pushEnabled,
            'previousState.pushEnabled',
            true),
      ],
    );

    blocTest<ProfileBloc, ProfileState>(
      'PhoneUpdateRequested : émet [Loaded(phoneUpdating), Loaded(compte à '
      'jour)] quand updateAccount réussit (#4544)',
      build: () {
        final mockUpdateAccount = MockUpdateAccountUseCase();
        when(() => mockUpdateAccount(phone: '+33698765432')).thenAnswer(
          (_) async => const Right(PatientAccount(
            id: 'acc-1',
            firstName: 'Marie',
            lastName: 'Curie',
            email: 'marie@example.com',
            phone: '+33698765432',
          )),
        );
        return _makeBloc(
            mockGetAccount, mockUserSettings, mockNotifRepo, mockUpdateAccount);
      },
      seed: () => const ProfileLoaded(_account,
          biometricEnabled: false, notifPrefs: _prefs),
      act: (bloc) => bloc.add(const PhoneUpdateRequested('+33698765432')),
      expect: () => [
        isA<ProfileLoaded>()
            .having((s) => s.phoneUpdating, 'phoneUpdating', true),
        isA<ProfileLoaded>()
            .having((s) => s.account.phone, 'account.phone', '+33698765432')
            .having((s) => s.phoneUpdating, 'phoneUpdating', false),
      ],
    );

    blocTest<ProfileBloc, ProfileState>(
      'PhoneUpdateRequested : émet [Loaded(phoneUpdating), ToggleFailed] '
      'quand updateAccount échoue — le téléphone précédent est conservé '
      '(#4544)',
      build: () {
        final mockUpdateAccount = MockUpdateAccountUseCase();
        when(() => mockUpdateAccount(phone: 'invalide')).thenAnswer(
          (_) async => const Left(ValidationFailure(
            message: 'Numéro de téléphone invalide.',
          )),
        );
        return _makeBloc(
            mockGetAccount, mockUserSettings, mockNotifRepo, mockUpdateAccount);
      },
      seed: () => const ProfileLoaded(_account,
          biometricEnabled: false, notifPrefs: _prefs),
      act: (bloc) => bloc.add(const PhoneUpdateRequested('invalide')),
      expect: () => [
        isA<ProfileLoaded>()
            .having((s) => s.phoneUpdating, 'phoneUpdating', true),
        isA<ProfileToggleFailed>()
            .having((s) => s.previousState.account.phone,
                'previousState.account.phone', '0601020304')
            .having(
                (s) => s.message, 'message', 'Numéro de téléphone invalide.'),
      ],
    );
  });
}
