import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/appointments/appointments_bloc.dart';
import 'package:app_patient/features/appointments/appointments_event.dart';
import 'package:app_patient/features/appointments/appointments_page.dart';
import 'package:app_patient/features/appointments/appointments_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockSearchProvidersUseCase extends Mock
    implements SearchProvidersUseCase {}

class MockSearchSlotsUseCase extends Mock implements SearchSlotsUseCase {}

class MockHoldSlotUseCase extends Mock implements HoldSlotUseCase {}

class MockConfirmBookingUseCase extends Mock implements ConfirmBookingUseCase {}

class _MockAppointmentsBloc
    extends MockBloc<AppointmentsEvent, AppointmentsState>
    implements AppointmentsBloc {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(AppointmentsBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(body: AppointmentsPage()),
      ),
    );

AppointmentsBloc _makeBloc({
  required MockSearchProvidersUseCase searchProviders,
  required MockSearchSlotsUseCase searchSlots,
  required MockHoldSlotUseCase holdSlot,
  required MockConfirmBookingUseCase confirmBooking,
}) =>
    AppointmentsBloc(
      searchProviders: searchProviders,
      searchSlots: searchSlots,
      holdSlot: holdSlot,
      confirmBooking: confirmBooking,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
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
        home: BlocProvider<AppointmentsBloc>.value(
          value: bloc,
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
        home: BlocProvider<AppointmentsBloc>.value(
          value: bloc,
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
        home: BlocProvider<AppointmentsBloc>.value(
          value: bloc,
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
        home: BlocProvider<AppointmentsBloc>.value(
          value: bloc,
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
      'jan', 'fév', 'mar', 'avr', 'mai', 'jun',
      'jul', 'aoû', 'sep', 'oct', 'nov', 'déc',
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
        home: BlocProvider<AppointmentsBloc>.value(
          value: bloc,
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
        home: BlocProvider<AppointmentsBloc>.value(
          value: bloc,
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
        home: BlocProvider<AppointmentsBloc>.value(
          value: bloc,
          child: const Scaffold(body: AppointmentsPage()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Demande de rendez-vous envoyée'), findsOneWidget);
      expect(find.textContaining('confirmé'), findsNothing);
    });
  });
}
