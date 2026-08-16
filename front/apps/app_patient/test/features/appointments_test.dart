import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/appointments/appointments_bloc.dart';
import 'package:app_patient/features/appointments/appointments_event.dart';
import 'package:app_patient/features/appointments/appointments_page.dart';
import 'package:app_patient/features/appointments/appointments_state.dart';
import 'package:app_patient/session/auth_cubit.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockSearchProvidersUseCase extends Mock
    implements SearchProvidersUseCase {}

class MockSearchSlotsUseCase extends Mock implements SearchSlotsUseCase {}

class MockHoldSlotUseCase extends Mock implements HoldSlotUseCase {}

class MockConfirmBookingUseCase extends Mock implements ConfirmBookingUseCase {}

class MockRegisterUseCase extends Mock implements RegisterUseCase {}

class MockUpdateAccountUseCase extends Mock implements UpdateAccountUseCase {}

class MockUpdateNotificationPreferencesUseCase extends Mock
    implements UpdateNotificationPreferencesUseCase {}

class _MockAppointmentsBloc
    extends MockBloc<AppointmentsEvent, AppointmentsState>
    implements AppointmentsBloc {}

class MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _authenticatedState = AuthAuthenticated(
  AuthSession(kind: UserKind.patient, userId: 'u1', accountId: 'acc-1'),
);

/// #5362 : `_BookingPanel` lit `AuthCubit` (context.watch) pour savoir si le
/// formulaire « Vos informations » + création de compte doit s'afficher —
/// tout test qui monte [AppointmentsPage] doit donc fournir un AuthCubit.
/// Authentifié par défaut (comportement historique, pré-#5362, inchangé) ;
/// passer [authState] pour couvrir le parcours visiteur anonyme.
MockAuthCubit _makeAuthCubit([AuthState authState = _authenticatedState]) {
  final cubit = MockAuthCubit();
  when(() => cubit.state).thenReturn(authState);
  whenListen(cubit, const Stream<AuthState>.empty(), initialState: authState);
  return cubit;
}

Widget _wrap(AppointmentsBloc bloc, {AuthState? authState}) => MaterialApp(
      theme: NubiaTheme.light,
      home: MultiBlocProvider(
        providers: [
          BlocProvider<AppointmentsBloc>.value(value: bloc),
          BlocProvider<AuthCubit>.value(
            value: _makeAuthCubit(authState ?? _authenticatedState),
          ),
        ],
        child: const Scaffold(body: AppointmentsPage()),
      ),
    );

AppointmentsBloc _makeBloc({
  required MockSearchProvidersUseCase searchProviders,
  required MockSearchSlotsUseCase searchSlots,
  required MockHoldSlotUseCase holdSlot,
  required MockConfirmBookingUseCase confirmBooking,
  MockRegisterUseCase? register,
  MockUpdateAccountUseCase? updateAccount,
  MockUpdateNotificationPreferencesUseCase? updateNotificationPreferences,
  MockAuthCubit? authCubit,
}) =>
    AppointmentsBloc(
      searchProviders: searchProviders,
      searchSlots: searchSlots,
      holdSlot: holdSlot,
      confirmBooking: confirmBooking,
      register: register ?? MockRegisterUseCase(),
      updateAccount: updateAccount ?? MockUpdateAccountUseCase(),
      updateNotificationPreferences: updateNotificationPreferences ??
          MockUpdateNotificationPreferencesUseCase(),
      authCubit: authCubit ?? _makeAuthCubit(),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(const NotificationPreferences.allEnabled());
  });

  late MockSearchProvidersUseCase mockSearchProviders;
  late MockSearchSlotsUseCase mockSearchSlots;
  late MockHoldSlotUseCase mockHoldSlot;
  late MockConfirmBookingUseCase mockConfirmBooking;

  setUp(() {
    mockSearchProviders = MockSearchProvidersUseCase();
    mockSearchSlots = MockSearchSlotsUseCase();
    mockHoldSlot = MockHoldSlotUseCase();
    mockConfirmBooking = MockConfirmBookingUseCase();
  });

  group('AppointmentsPage', () {
    testWidgets('affiche le champ de recherche en état initial',
        (tester) async {
      final bloc = _makeBloc(
        searchProviders: mockSearchProviders,
        searchSlots: mockSearchSlots,
        holdSlot: mockHoldSlot,
        confirmBooking: mockConfirmBooking,
      );

      await tester.pumpWidget(_wrap(bloc));

      expect(find.byKey(const Key('search_field')), findsOneWidget);
    });

    testWidgets(
        'affiche "Aucun praticien trouvé." quand la recherche renvoie une liste vide',
        (tester) async {
      when(() => mockSearchProviders(query: any(named: 'query')))
          .thenAnswer((_) async => const Right([]));

      final bloc = _makeBloc(
        searchProviders: mockSearchProviders,
        searchSlots: mockSearchSlots,
        holdSlot: mockHoldSlot,
        confirmBooking: mockConfirmBooking,
      );

      bloc.add(const AppointmentsSearchChanged('dentiste'));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('empty_providers')), findsOneWidget);
    });

    testWidgets('affiche la liste des praticiens quand la recherche réussit',
        (tester) async {
      const provider = ProviderResult(
        id: 'prov-1',
        displayName: 'Dr Dupont',
        specialty: 'Dentiste',
      );
      when(() => mockSearchProviders(query: any(named: 'query')))
          .thenAnswer((_) async => const Right([provider]));

      final bloc = _makeBloc(
        searchProviders: mockSearchProviders,
        searchSlots: mockSearchSlots,
        holdSlot: mockHoldSlot,
        confirmBooking: mockConfirmBooking,
      );

      bloc.add(const AppointmentsSearchChanged('dentiste'));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.text('Dr Dupont'), findsOneWidget);
    });
  });

  group('filtre local praticiens', () {
    late _MockAppointmentsBloc bloc;

    const providers = [
      ProviderResult(id: 'p1', displayName: 'Dr Martin', specialty: 'Dentiste'),
      ProviderResult(
          id: 'p2', displayName: 'Dr Dupont', specialty: 'Chirurgien'),
      ProviderResult(
          id: 'p3', displayName: 'Dr Bernard', specialty: 'Orthodontiste'),
    ];

    setUp(() {
      bloc = _MockAppointmentsBloc();
    });

    testWidgets('affiche la liste des praticiens chargés', (tester) async {
      when(() => bloc.state).thenReturn(
        const AppointmentsProvidersLoaded(
            providers: providers, query: 'dentiste'),
      );
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<AppointmentsBloc>.value(value: bloc),
            BlocProvider<AuthCubit>.value(value: _makeAuthCubit()),
          ],
          child: const Scaffold(body: AppointmentsPage()),
        ),
      ));
      await tester.pumpAndSettle();

      // Barre de recherche persistante + les 3 praticiens (ProviderCard).
      expect(find.byKey(const Key('search_field')), findsOneWidget);
      expect(find.byType(ProviderCard), findsNWidgets(3));
      expect(find.text('Dr Martin'), findsOneWidget);
    });

    testWidgets('affiche la carte plein écran + chips de filtres rapides',
        (tester) async {
      when(() => bloc.state).thenReturn(
        const AppointmentsProvidersLoaded(
            providers: providers, query: 'dentiste'),
      );
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<AppointmentsBloc>.value(value: bloc),
            BlocProvider<AuthCubit>.value(value: _makeAuthCubit()),
          ],
          child: const Scaffold(body: AppointmentsPage()),
        ),
      ));
      await tester.pumpAndSettle();

      // Carte immersive + feuille de résultats + chips.
      expect(find.byKey(const Key('providers_map')), findsOneWidget);
      expect(find.byKey(const Key('providers_list')), findsOneWidget);
      expect(find.byKey(const Key('quick_filters')), findsOneWidget);
    });

    testWidgets(
        'tap sur une ProviderCard ouvre le détail « Voir les créneaux »',
        (tester) async {
      when(() => bloc.state).thenReturn(
        const AppointmentsProvidersLoaded(
            providers: providers, query: 'dentiste'),
      );
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<AppointmentsBloc>.value(value: bloc),
            BlocProvider<AuthCubit>.value(value: _makeAuthCubit()),
          ],
          child: const Scaffold(body: AppointmentsPage()),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('provider_p1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sheet_see_slots')), findsOneWidget);
      expect(find.text('Voir les créneaux'), findsOneWidget);
    });
  });

  group('AppointmentsBloc', () {
    blocTest<AppointmentsBloc, AppointmentsState>(
      'émet [SearchLoading, ProvidersLoaded(empty)] quand la recherche renvoie []',
      build: () {
        when(() => mockSearchProviders(query: any(named: 'query')))
            .thenAnswer((_) async => const Right([]));
        return _makeBloc(
          searchProviders: mockSearchProviders,
          searchSlots: mockSearchSlots,
          holdSlot: mockHoldSlot,
          confirmBooking: mockConfirmBooking,
        );
      },
      act: (bloc) => bloc.add(const AppointmentsSearchChanged('ortho')),
      expect: () => [
        const AppointmentsSearchLoading(),
        isA<AppointmentsProvidersLoaded>()
            .having((s) => s.providers, 'providers', isEmpty),
      ],
    );

    blocTest<AppointmentsBloc, AppointmentsState>(
      'query vide = annuaire par défaut (charge quand même des praticiens)',
      build: () {
        when(() => mockSearchProviders(query: any(named: 'query')))
            .thenAnswer((_) async => const Right([]));
        return _makeBloc(
          searchProviders: mockSearchProviders,
          searchSlots: mockSearchSlots,
          holdSlot: mockHoldSlot,
          confirmBooking: mockConfirmBooking,
        );
      },
      act: (bloc) => bloc.add(const AppointmentsSearchChanged('')),
      expect: () => [
        const AppointmentsSearchLoading(),
        isA<AppointmentsProvidersLoaded>(),
      ],
      verify: (_) => verify(() => mockSearchProviders(query: '')).called(1),
    );

    blocTest<AppointmentsBloc, AppointmentsState>(
      'émet [Error] quand la recherche échoue',
      build: () {
        when(() => mockSearchProviders(query: any(named: 'query'))).thenAnswer(
            (_) async => const Left(NetworkFailure('Erreur réseau.')));
        return _makeBloc(
          searchProviders: mockSearchProviders,
          searchSlots: mockSearchSlots,
          holdSlot: mockHoldSlot,
          confirmBooking: mockConfirmBooking,
        );
      },
      act: (bloc) => bloc.add(const AppointmentsSearchChanged('dentiste')),
      expect: () => [
        const AppointmentsSearchLoading(),
        isA<AppointmentsError>(),
      ],
    );

    // #5363 — la sélection d'un créneau pose un hold de 10 min ; le
    // décompte visible du récapitulatif a besoin de holdExpiresAt.
    final provider = const ProviderResult(
      id: 'p1',
      displayName: 'Dr Martin',
      specialty: 'Dentiste',
    );
    final slot = Slot(
      id: 's1',
      cabinetId: 'cab-1',
      practitionerId: 'prac-1',
      startsAt: DateTime(2026, 7, 10, 9, 0),
      endsAt: DateTime(2026, 7, 10, 9, 30),
      isAvailable: true,
    );

    blocTest<AppointmentsBloc, AppointmentsState>(
      'AppointmentsSlotSelected renseigne holdToken et holdExpiresAt (#5363)',
      build: () {
        final expiresAt = DateTime(2026, 7, 10, 8, 50);
        when(() => mockHoldSlot(any())).thenAnswer(
          (_) async => Right(SlotHold(token: 'hold-1', expiresAt: expiresAt)),
        );
        return _makeBloc(
          searchProviders: mockSearchProviders,
          searchSlots: mockSearchSlots,
          holdSlot: mockHoldSlot,
          confirmBooking: mockConfirmBooking,
        );
      },
      seed: () => AppointmentsSlotsLoaded(provider: provider, slots: [slot]),
      act: (bloc) => bloc.add(AppointmentsSlotSelected(slot)),
      expect: () => [
        isA<AppointmentsSlotsLoaded>()
            .having((s) => s.holdToken, 'holdToken', 'hold-1')
            .having((s) => s.holdExpiresAt, 'holdExpiresAt',
                DateTime(2026, 7, 10, 8, 50)),
      ],
    );

    blocTest<AppointmentsBloc, AppointmentsState>(
      'AppointmentsHoldExpired relâche le créneau sélectionné (#5363)',
      build: () => _makeBloc(
        searchProviders: mockSearchProviders,
        searchSlots: mockSearchSlots,
        holdSlot: mockHoldSlot,
        confirmBooking: mockConfirmBooking,
      ),
      seed: () => AppointmentsSlotsLoaded(
        provider: provider,
        slots: [slot],
        selectedSlot: slot,
        holdToken: 'hold-1',
        holdExpiresAt: DateTime(2026, 7, 10, 8, 50),
      ),
      act: (bloc) => bloc.add(const AppointmentsHoldExpired()),
      expect: () => [
        isA<AppointmentsSlotsLoaded>()
            .having((s) => s.selectedSlot, 'selectedSlot', isNull)
            .having((s) => s.holdToken, 'holdToken', isNull)
            .having((s) => s.holdExpiresAt, 'holdExpiresAt', isNull),
      ],
    );

    // #5362 — « le compte se crée avec le rendez-vous, jamais avant » : un
    // visiteur anonyme peut sélectionner un créneau sans hold réseau (pas de
    // session patient pour le poser), puis le compte + le hold se posent
    // tous deux à la confirmation, dans le même geste.
    group('visiteur anonyme (#5362)', () {
      late MockAuthCubit anonAuthCubit;
      late MockRegisterUseCase mockRegister;
      late MockUpdateAccountUseCase mockUpdateAccount;
      late MockUpdateNotificationPreferencesUseCase mockUpdateNotifPrefs;

      setUp(() {
        anonAuthCubit = _makeAuthCubit(const AuthUnauthenticated());
        mockRegister = MockRegisterUseCase();
        mockUpdateAccount = MockUpdateAccountUseCase();
        mockUpdateNotifPrefs = MockUpdateNotificationPreferencesUseCase();
        when(() => anonAuthCubit.restore()).thenAnswer((_) async {});
      });

      blocTest<AppointmentsBloc, AppointmentsState>(
        'AppointmentsSlotSelected ne pose aucun hold réseau (pas de session)',
        build: () => _makeBloc(
          searchProviders: mockSearchProviders,
          searchSlots: mockSearchSlots,
          holdSlot: mockHoldSlot,
          confirmBooking: mockConfirmBooking,
          register: mockRegister,
          updateAccount: mockUpdateAccount,
          updateNotificationPreferences: mockUpdateNotifPrefs,
          authCubit: anonAuthCubit,
        ),
        seed: () => AppointmentsSlotsLoaded(provider: provider, slots: [slot]),
        act: (bloc) => bloc.add(AppointmentsSlotSelected(slot)),
        expect: () => [
          isA<AppointmentsSlotsLoaded>()
              .having((s) => s.selectedSlot, 'selectedSlot', slot)
              .having((s) => s.holdToken, 'holdToken', isNull),
        ],
        verify: (_) => verifyNever(() => mockHoldSlot(any())),
      );

      blocTest<AppointmentsBloc, AppointmentsState>(
        'AppointmentsBookingConfirmed crée le compte puis pose le hold '
        'avant de réserver',
        build: () {
          when(() => mockRegister(
                email: any(named: 'email'),
                password: any(named: 'password'),
                acceptCgu: any(named: 'acceptCgu'),
                cguVersion: any(named: 'cguVersion'),
              )).thenAnswer((_) async => const Right(PatientAccount(
                id: 'acc-1',
                firstName: 'Alice',
                lastName: 'Martin',
                email: 'alice@example.com',
              )));
          when(() => mockUpdateAccount(
                firstName: any(named: 'firstName'),
                lastName: any(named: 'lastName'),
                phone: any(named: 'phone'),
                dateOfBirth: any(named: 'dateOfBirth'),
              )).thenAnswer((_) async => const Right(PatientAccount(
                id: 'acc-1',
                firstName: 'Alice',
                lastName: 'Martin',
                email: 'alice@example.com',
              )));
          when(() => mockUpdateNotifPrefs(any()))
              .thenAnswer((_) async => const Right(null));
          when(() => mockHoldSlot(any())).thenAnswer((_) async => Right(
                SlotHold(
                    token: 'hold-guest',
                    expiresAt: DateTime(2026, 7, 10, 8, 50)),
              ));
          when(() => mockConfirmBooking(
                slotId: any(named: 'slotId'),
                holdToken: any(named: 'holdToken'),
                motif: any(named: 'motif'),
                idempotencyKey: any(named: 'idempotencyKey'),
              )).thenAnswer((_) async => const Right('appt-1'));
          return _makeBloc(
            searchProviders: mockSearchProviders,
            searchSlots: mockSearchSlots,
            holdSlot: mockHoldSlot,
            confirmBooking: mockConfirmBooking,
            register: mockRegister,
            updateAccount: mockUpdateAccount,
            updateNotificationPreferences: mockUpdateNotifPrefs,
            authCubit: anonAuthCubit,
          );
        },
        seed: () => AppointmentsSlotsLoaded(
          provider: provider,
          slots: [slot],
          selectedSlot: slot,
          motif: 'Contrôle',
        ),
        act: (bloc) => bloc.add(AppointmentsBookingConfirmed(
          firstName: 'Alice',
          lastName: 'Martin',
          dateOfBirth: DateTime(1990, 1, 1),
          phone: '0612345678',
          email: 'alice@example.com',
          createAccount: true,
          cguAccepted: true,
        )),
        expect: () => [
          const AppointmentsBookingLoading(),
          isA<AppointmentsBookingSuccess>()
              .having((s) => s.appointment.id, 'id', 'appt-1'),
        ],
        verify: (_) {
          verify(() => mockRegister(
                email: 'alice@example.com',
                password: any(named: 'password'),
                acceptCgu: true,
                cguVersion: any(named: 'cguVersion'),
              )).called(1);
          verify(() => anonAuthCubit.restore()).called(1);
          verify(() => mockHoldSlot(slot.id)).called(1);
          verify(() => mockConfirmBooking(
                slotId: slot.id,
                holdToken: 'hold-guest',
                motif: any(named: 'motif'),
                idempotencyKey: any(named: 'idempotencyKey'),
              )).called(1);
        },
      );

      blocTest<AppointmentsBloc, AppointmentsState>(
        'échec de création de compte -> Error, sans poser de hold ni réserver',
        build: () {
          when(() => mockRegister(
                    email: any(named: 'email'),
                    password: any(named: 'password'),
                    acceptCgu: any(named: 'acceptCgu'),
                    cguVersion: any(named: 'cguVersion'),
                  ))
              .thenAnswer((_) async =>
                  const Left(NetworkFailure('email déjà utilisé')));
          return _makeBloc(
            searchProviders: mockSearchProviders,
            searchSlots: mockSearchSlots,
            holdSlot: mockHoldSlot,
            confirmBooking: mockConfirmBooking,
            register: mockRegister,
            updateAccount: mockUpdateAccount,
            updateNotificationPreferences: mockUpdateNotifPrefs,
            authCubit: anonAuthCubit,
          );
        },
        seed: () => AppointmentsSlotsLoaded(
          provider: provider,
          slots: [slot],
          selectedSlot: slot,
          motif: 'Contrôle',
        ),
        act: (bloc) => bloc.add(AppointmentsBookingConfirmed(
          firstName: 'Alice',
          lastName: 'Martin',
          dateOfBirth: DateTime(1990, 1, 1),
          phone: '0612345678',
          email: 'alice@example.com',
          createAccount: true,
          cguAccepted: true,
        )),
        expect: () => [
          const AppointmentsBookingLoading(),
          isA<AppointmentsError>(),
        ],
        verify: (_) {
          verifyNever(() => mockHoldSlot(any()));
          verifyNever(() => mockConfirmBooking(
                slotId: any(named: 'slotId'),
                holdToken: any(named: 'holdToken'),
                motif: any(named: 'motif'),
                idempotencyKey: any(named: 'idempotencyKey'),
              ));
        },
      );
    });
  });

  // #3418 — les créneaux d'une même période (Matin / Après-midi) doivent
  // s'afficher en grille (Wrap, plusieurs par ligne), pas en colonne unique.
  group('créneaux en grille (#3418)', () {
    Slot slot(String id, DateTime at) => Slot(
          id: id,
          cabinetId: 'cab-1',
          practitionerId: 'prac-1',
          startsAt: at,
          endsAt: at.add(const Duration(minutes: 30)),
          isAvailable: true,
        );

    testWidgets('les SlotChip d\'une période sont côte à côte (Wrap)',
        (tester) async {
      final day = DateTime(2026, 7, 10);
      final bloc = _MockAppointmentsBloc();
      when(() => bloc.state).thenReturn(
        AppointmentsSlotsLoaded(
          provider: const ProviderResult(
            id: 'p1',
            displayName: 'Dr Martin',
            specialty: 'Dentiste',
          ),
          slots: [
            slot('s1', DateTime(day.year, day.month, day.day, 9, 0)),
            slot('s2', DateTime(day.year, day.month, day.day, 9, 30)),
            slot('s3', DateTime(day.year, day.month, day.day, 10, 0)),
            slot('s4', DateTime(day.year, day.month, day.day, 14, 0)),
            slot('s5', DateTime(day.year, day.month, day.day, 14, 30)),
          ],
        ),
      );
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<AppointmentsBloc>.value(value: bloc),
            BlocProvider<AuthCubit>.value(value: _makeAuthCubit()),
          ],
          child: const Scaffold(body: AppointmentsPage()),
        ),
      ));
      await tester.pumpAndSettle();

      // Sections de période présentes + tous les créneaux rendus en SlotChip.
      expect(find.text('Matin'), findsOneWidget);
      expect(find.text('Après-midi'), findsOneWidget);
      expect(find.byType(SlotChip), findsNWidgets(5));
      expect(find.byType(Wrap), findsWidgets);

      // Deux créneaux du matin sont sur la même ligne (même y, x différents) :
      // preuve d'une vraie grille et non d'une colonne pleine largeur.
      final c1 = tester.getCenter(find.text('09:00'));
      final c2 = tester.getCenter(find.text('09:30'));
      expect(c1.dy, moreOrLessEquals(c2.dy, epsilon: 0.5));
      expect(c1.dx, isNot(moreOrLessEquals(c2.dx, epsilon: 0.5)));
    });
  });

  // #5365 — tunnel web : les puces de créneau restent pilotées par
  // Slot.isAvailable et les 3 états de SlotChip (available/selected/
  // unavailable), la puce indisponible affichant « — » (pas l'heure barrée).
  group('états SlotChip pilotés par Slot.isAvailable (#5365)', () {
    testWidgets(
        'créneau indisponible : puce SlotChip.unavailable avec contenu « — »',
        (tester) async {
      final day = DateTime(2026, 7, 10);
      final bloc = _MockAppointmentsBloc();
      when(() => bloc.state).thenReturn(
        AppointmentsSlotsLoaded(
          provider: const ProviderResult(
            id: 'p1',
            displayName: 'Dr Martin',
            specialty: 'Dentiste',
          ),
          slots: [
            Slot(
              id: 's1',
              cabinetId: 'cab-1',
              practitionerId: 'prac-1',
              startsAt: DateTime(day.year, day.month, day.day, 9, 0),
              endsAt: DateTime(day.year, day.month, day.day, 9, 30),
              isAvailable: false,
            ),
          ],
        ),
      );
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.text('09:00'), findsNothing);
      expect(find.text('—'), findsOneWidget);

      final chip = tester.widget<SlotChip>(find.byType(SlotChip));
      expect(chip.state, SlotChipState.unavailable);
    });
  });

  // #5366 — la conversion .toLocal() doit être appliquée avant tout
  // regroupement/affichage d'heure dans le tunnel de réservation, sans
  // exception. Un créneau proche de minuit UTC doit apparaître sous le jour
  // calendaire LOCAL, jamais sous le jour UTC brut.
  group('regroupement par jour en heure locale (#5366)', () {
    const weekdays = ['Lun.', 'Mar.', 'Mer.', 'Jeu.', 'Ven.', 'Sam.', 'Dim.'];
    const months = [
      'jan',
      'fév',
      'mar',
      'avr',
      'mai',
      'jun',
      'jul',
      'aoû',
      'sep',
      'oct',
      'nov',
      'déc',
    ];
    String dayHeaderOf(DateTime dt) =>
        '${weekdays[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]}';
    String hhmmOf(DateTime dt) =>
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    testWidgets(
        'un créneau proche de minuit UTC est affiché sous le jour local, '
        'pas le jour UTC brut', (tester) async {
      final startsAt = DateTime.utc(2026, 8, 16, 23, 50);
      final localStartsAt = startsAt.toLocal();
      final expectedDayHeader = dayHeaderOf(localStartsAt);
      final expectedHHmm = hhmmOf(localStartsAt);
      final rawUtcDayHeader = dayHeaderOf(startsAt);

      final bloc = _MockAppointmentsBloc();
      when(() => bloc.state).thenReturn(
        AppointmentsSlotsLoaded(
          provider: const ProviderResult(
            id: 'p1',
            displayName: 'Dr Martin',
            specialty: 'Dentiste',
          ),
          slots: [
            Slot(
              id: 's1',
              cabinetId: 'cab-1',
              practitionerId: 'prac-1',
              startsAt: startsAt,
              endsAt: startsAt.add(const Duration(minutes: 30)),
              isAvailable: true,
            ),
          ],
        ),
      );
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<AppointmentsBloc>.value(value: bloc),
            BlocProvider<AuthCubit>.value(value: _makeAuthCubit()),
          ],
          child: const Scaffold(body: AppointmentsPage()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text(expectedDayHeader),
        findsOneWidget,
        reason: 'l\'en-tête de jour doit refléter le jour local '
            '($expectedDayHeader), pas le jour UTC brut ($rawUtcDayHeader)',
      );
      expect(find.textContaining(expectedHHmm), findsOneWidget);
      if (expectedDayHeader != rawUtcDayHeader) {
        expect(find.text(rawUtcDayHeader), findsNothing);
      }
    });
  });

  // #3825 — pas de séparateur « · » ni de ligne résiduelle dans l'en-tête
  // praticien (fiche/hero) quand la spécialité est vide.
  group('en-tête praticien sans spécialité (#3825)', () {
    testWidgets('affiche uniquement le nom du praticien', (tester) async {
      final bloc = _MockAppointmentsBloc();
      when(() => bloc.state).thenReturn(
        const AppointmentsSlotsLoaded(
          provider: ProviderResult(
            id: 'p1',
            displayName: 'Dr Amélie Rousseau',
            specialty: '',
          ),
          slots: [],
        ),
      );
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<AppointmentsBloc>.value(value: bloc),
            BlocProvider<AuthCubit>.value(value: _makeAuthCubit()),
          ],
          child: const Scaffold(body: AppointmentsPage()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Dr Amélie Rousseau'), findsOneWidget);
      expect(find.text(''), findsNothing);
    });
  });

  // #3420 — après réservation, le RDV est en attente (le cabinet confirme) :
  // le toast doit annoncer une DEMANDE, pas une confirmation.
  group('toast de réservation (#3420)', () {
    testWidgets('affiche « Demande de rendez-vous envoyée », pas « confirmé »',
        (tester) async {
      final appt = Appointment(
        id: 'rdv-1',
        cabinetId: 'cab-1',
        practitionerName: 'Dr Martin',
        practitionerSpecialty: 'Dentiste',
        startsAt: DateTime(2026, 7, 10, 9, 0),
        duration: const Duration(minutes: 30),
        motif: 'Contrôle',
        status: AppointmentStatus.requested,
      );

      final bloc = _MockAppointmentsBloc();
      whenListen(
        bloc,
        Stream<AppointmentsState>.fromIterable([
          AppointmentsBookingSuccess(appt),
        ]),
        initialState: const AppointmentsBookingLoading(),
      );

      await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<AppointmentsBloc>.value(value: bloc),
            BlocProvider<AuthCubit>.value(value: _makeAuthCubit()),
          ],
          child: const Scaffold(body: AppointmentsPage()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Demande de rendez-vous envoyée'), findsOneWidget);
      expect(find.textContaining('confirmé'), findsNothing);
    });
  });

  // #5363 — verrou de 10 min sur le créneau sélectionné, avec décompte
  // visible dans le récapitulatif.
  group('verrou 10 min avec décompte visible (#5363)', () {
    final provider = const ProviderResult(
      id: 'p1',
      displayName: 'Dr Martin',
      specialty: 'Dentiste',
    );
    final slot = Slot(
      id: 's1',
      cabinetId: 'cab-1',
      practitionerId: 'prac-1',
      startsAt: DateTime(2026, 7, 10, 9, 0),
      endsAt: DateTime(2026, 7, 10, 9, 30),
      isAvailable: true,
    );

    testWidgets(
        'affiche le sous-titre "retenu pendant 10 minutes" et le décompte '
        'vivant une fois un créneau sélectionné', (tester) async {
      final bloc = _MockAppointmentsBloc();
      when(() => bloc.state).thenReturn(
        AppointmentsSlotsLoaded(
          provider: provider,
          slots: [slot],
          selectedSlot: slot,
          holdToken: 'hold-1',
          holdExpiresAt:
              DateTime.now().add(const Duration(minutes: 9, seconds: 30)),
        ),
      );
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(
        find.text('Votre rendez-vous est retenu pendant 10 minutes.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('booking_hold_countdown')), findsOneWidget);
      final text = tester
          .widget<Text>(find.descendant(
            of: find.byKey(const Key('booking_hold_countdown')),
            matching: find.byType(Text),
          ))
          .data!;
      expect(
        text,
        matches(RegExp(
          r'^Ce créneau vous est réservé pendant \d+ min \d+ s\. '
          r'Passé ce délai, il redevient disponible\.$',
        )),
      );

      // Le Timer périodique doit être annulé proprement (sinon la
      // suite échoue avec un "pending timer" une fois le widget démonté).
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("à expiration, informe l'utilisateur et relâche la sélection",
        (tester) async {
      final bloc = _MockAppointmentsBloc();
      when(() => bloc.state).thenReturn(
        AppointmentsSlotsLoaded(
          provider: provider,
          slots: [slot],
          selectedSlot: slot,
          holdToken: 'hold-1',
          holdExpiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      );
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      verify(() => bloc.add(const AppointmentsHoldExpired())).called(1);
      expect(find.textContaining("vient d'être libéré"), findsOneWidget);
    });
  });

  // #5362 — le formulaire de confirmation crée le compte dans le même
  // écran/CTA pour un visiteur anonyme, jamais pour un patient déjà connecté.
  group('formulaire « Vos informations » (#5362)', () {
    final provider = const ProviderResult(
      id: 'p1',
      displayName: 'Dr Martin',
      specialty: 'Dentiste',
    );
    final slot = Slot(
      id: 's1',
      cabinetId: 'cab-1',
      practitionerId: 'prac-1',
      startsAt: DateTime(2026, 7, 10, 9, 0),
      endsAt: DateTime(2026, 7, 10, 9, 30),
      isAvailable: true,
    );

    testWidgets(
        'visiteur anonyme : affiche « Pour qui est ce rendez-vous ? » et '
        'les options de compte', (tester) async {
      final bloc = _MockAppointmentsBloc();
      when(() => bloc.state).thenReturn(
        AppointmentsSlotsLoaded(
          provider: provider,
          slots: [slot],
          selectedSlot: slot,
        ),
      );
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

      await tester
          .pumpWidget(_wrap(bloc, authState: const AuthUnauthenticated()));
      await tester.pumpAndSettle();

      expect(find.text('Pour qui est ce rendez-vous ?'), findsOneWidget);
      expect(find.byKey(const Key('booking_first_name')), findsOneWidget);
      expect(find.byKey(const Key('booking_email')), findsOneWidget);
      expect(find.text('Je crée mon compte Nubia'), findsOneWidget);
      expect(find.text('Rappels de rendez-vous'), findsOneWidget);
      expect(
        find.textContaining("J'accepte les Conditions Générales d'Utilisation"),
        findsOneWidget,
      );
      expect(find.textContaining('Aucune carte bancaire'), findsOneWidget);

      // CTA désactivé tant que les infos + CGU ne sont pas complètes.
      final button = tester
          .widget<NubiaButton>(find.byKey(const Key('confirm_booking_button')));
      expect(button.onPressed, isNull);
    });

    testWidgets(
        'patient déjà connecté : ne réaffiche jamais le formulaire '
        "d'inscription", (tester) async {
      final bloc = _MockAppointmentsBloc();
      when(() => bloc.state).thenReturn(
        AppointmentsSlotsLoaded(
          provider: provider,
          slots: [slot],
          selectedSlot: slot,
          holdToken: 'hold-1',
          motif: 'Contrôle',
        ),
      );
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.text('Pour qui est ce rendez-vous ?'), findsNothing);
      expect(find.byKey(const Key('booking_first_name')), findsNothing);
      expect(find.text('Je crée mon compte Nubia'), findsNothing);

      // Le motif est déjà rempli côté state -> CTA activable.
      final button = tester
          .widget<NubiaButton>(find.byKey(const Key('confirm_booking_button')));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('le tunnel de recherche est accessible sans compte (#5362)',
        (tester) async {
      final bloc = _MockAppointmentsBloc();
      when(() => bloc.state).thenReturn(
        const AppointmentsProvidersLoaded(providers: [], query: ''),
      );
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

      await tester
          .pumpWidget(_wrap(bloc, authState: const AuthUnauthenticated()));
      await tester.pumpAndSettle();

      // La recherche reste utilisable sans qu'aucun flux d'inscription ne
      // s'interpose.
      expect(find.byKey(const Key('search_field')), findsOneWidget);
      expect(find.text('Pour qui est ce rendez-vous ?'), findsNothing);
    });
  });
}
