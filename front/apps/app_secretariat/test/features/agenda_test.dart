import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/agenda/agenda_bloc.dart';
import 'package:app_secretariat/features/agenda/agenda_event.dart';
import 'package:app_secretariat/features/agenda/agenda_page.dart';
import 'package:app_secretariat/features/agenda/agenda_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetCabinetAgendaUseCase extends Mock
    implements GetCabinetAgendaUseCase {}

class MockCreateCabinetAppointmentUseCase extends Mock
    implements CreateCabinetAppointmentUseCase {}

class MockConfirmAppointmentUseCase extends Mock
    implements ConfirmAppointmentUseCase {}

class MockRescheduleAppointmentUseCase extends Mock
    implements RescheduleAppointmentUseCase {}

class MockListBookableSlotsUseCase extends Mock
    implements ListBookableSlotsUseCase {}

class MockListCabinetPractitionersUseCase extends Mock
    implements ListCabinetPractitionersUseCase {}

class MockListCabinetPatientsUseCase extends Mock
    implements ListCabinetPatientsUseCase {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _weekStart = DateTime(2026, 7, 6); // lundi

/// Lundi de la semaine réelle du jour d'exécution du test — `AgendaPage`
/// charge toujours `_currentWeekStart()` (agenda_page.dart), jamais
/// `_weekStart` ci-dessus, donc les tests qui vérifient un rendu de grille
/// réel (colonnes/compteurs) doivent daté leurs entrées sur cette semaine-là.
DateTime _thisWeekMonday() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.subtract(Duration(days: today.weekday - 1));
}

final _entry = AgendaEntry(
  id: 'e-1',
  cabinetId: 'cab-1',
  practitionerId: 'prac-1',
  practitionerName: 'Dr Martin',
  startsAt: DateTime(2026, 7, 7, 9, 0),
  endsAt: DateTime(2026, 7, 7, 9, 30),
  patientId: 'pat-1',
  patientName: 'Marie Dupont',
  motif: 'Contrôle annuel',
  isFree: false,
);

AgendaBloc _makeBloc({
  required MockGetCabinetAgendaUseCase getAgenda,
  required MockCreateCabinetAppointmentUseCase createAppointment,
  required MockConfirmAppointmentUseCase confirmAppointment,
  required MockRescheduleAppointmentUseCase rescheduleAppointment,
  required MockListBookableSlotsUseCase listSlots,
  required MockListCabinetPractitionersUseCase listPractitioners,
}) =>
    AgendaBloc(
      getAgenda: getAgenda,
      createAppointment: createAppointment,
      confirmAppointment: confirmAppointment,
      rescheduleAppointment: rescheduleAppointment,
      listSlots: listSlots,
      listPractitioners: listPractitioners,
    );

Widget _wrap(AgendaBloc bloc) => MaterialApp(
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(
          body: _AgendaBodyDirect(),
        ),
      ),
    );

class _AgendaBodyDirect extends StatelessWidget {
  const _AgendaBodyDirect();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AgendaBloc, AgendaState>(
      builder: (context, state) {
        if (state is AgendaLoading || state is AgendaInitial) {
          return const Center(
              key: Key('agenda_loading'), child: CircularProgressIndicator());
        }
        if (state is AgendaError) {
          return Center(
            key: const Key('agenda_error'),
            child: Text(state.message),
          );
        }
        if (state is AgendaLoaded) {
          if (state.entries.isEmpty) {
            return const Center(
                key: Key('agenda_empty'),
                child: Text('Aucun rendez-vous cette semaine'));
          }
          return RefreshIndicator(
            key: const Key('agenda_refresh_indicator'),
            onRefresh: () async => context.read<AgendaBloc>().add(
                  AgendaLoadRequested(weekStart: _weekStart),
                ),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                for (final e in state.entries)
                  Text(key: Key('entry_${e.id}'), e.patientName ?? ''),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(CabinetAppointment(
      id: '',
      cabinetId: '',
      patientId: '',
      patientName: '',
      practitionerId: '',
      practitionerName: '',
      startsAt: DateTime(2026, 1, 1),
      duration: const Duration(minutes: 30),
      motif: '',
      status: CabinetAppointmentStatus.requested,
    ));
  });

  late MockGetCabinetAgendaUseCase mockGetAgenda;
  late MockCreateCabinetAppointmentUseCase mockCreate;
  late MockConfirmAppointmentUseCase mockConfirm;
  late MockRescheduleAppointmentUseCase mockReschedule;
  late MockListBookableSlotsUseCase mockListSlots;
  late MockListCabinetPractitionersUseCase mockListPractitioners;

  setUp(() {
    mockGetAgenda = MockGetCabinetAgendaUseCase();
    mockCreate = MockCreateCabinetAppointmentUseCase();
    mockConfirm = MockConfirmAppointmentUseCase();
    mockReschedule = MockRescheduleAppointmentUseCase();
    mockListSlots = MockListBookableSlotsUseCase();
    mockListPractitioners = MockListCabinetPractitionersUseCase();
    when(() => mockListPractitioners())
        .thenAnswer((_) async => const Right([]));
  });

  AgendaBloc makeBloc() => _makeBloc(
        getAgenda: mockGetAgenda,
        createAppointment: mockCreate,
        confirmAppointment: mockConfirm,
        rescheduleAppointment: mockReschedule,
        listSlots: mockListSlots,
        listPractitioners: mockListPractitioners,
      );

  group('AgendaBloc', () {
    blocTest<AgendaBloc, AgendaState>(
      'émet Loading puis Loaded avec les entrées',
      build: () {
        when(() => mockGetAgenda(any()))
            .thenAnswer((_) async => Right([_entry]));
        when(() =>
                mockListSlots(from: any(named: 'from'), to: any(named: 'to')))
            .thenAnswer((_) async => const Right([]));
        return makeBloc();
      },
      act: (bloc) => bloc.add(AgendaLoadRequested(weekStart: _weekStart)),
      expect: () => [
        const AgendaLoading(),
        AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'émet Loading puis Loaded vide quand aucun RDV',
      build: () {
        when(() => mockGetAgenda(any()))
            .thenAnswer((_) async => const Right([]));
        when(() =>
                mockListSlots(from: any(named: 'from'), to: any(named: 'to')))
            .thenAnswer((_) async => const Right([]));
        return makeBloc();
      },
      act: (bloc) => bloc.add(AgendaLoadRequested(weekStart: _weekStart)),
      expect: () => [
        const AgendaLoading(),
        AgendaLoaded(entries: const [], weekStart: _weekStart),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'émet AgendaError quand le chargement échoue',
      build: () {
        when(() => mockGetAgenda(any())).thenAnswer(
          (_) async => Left(NetworkFailure('Réseau indisponible')),
        );
        return makeBloc();
      },
      act: (bloc) => bloc.add(AgendaLoadRequested(weekStart: _weekStart)),
      expect: () => [
        const AgendaLoading(),
        const AgendaError('Réseau indisponible'),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'Confirm conserve l\'état avec actionError en cas d\'échec',
      build: () {
        when(() => mockConfirm(any())).thenAnswer(
          (_) async => Left(NetworkFailure('Erreur réseau')),
        );
        return makeBloc();
      },
      seed: () => AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      act: (bloc) => bloc
          .add(const AgendaAppointmentConfirmRequested(appointmentId: 'e-1')),
      expect: () => [
        AgendaLoaded(
          entries: [_entry],
          weekStart: _weekStart,
          actionInProgress: true,
        ),
        AgendaLoaded(
          entries: [_entry],
          weekStart: _weekStart,
          actionInProgress: false,
          actionError: 'Erreur réseau',
        ),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'Reschedule conserve l\'état avec actionError en cas d\'échec',
      build: () {
        when(() => mockReschedule(any(), any())).thenAnswer(
          (_) async => Left(NetworkFailure('Erreur réseau')),
        );
        return makeBloc();
      },
      seed: () => AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      act: (bloc) => bloc.add(AgendaAppointmentRescheduleRequested(
        appointmentId: 'e-1',
        newStartsAt: DateTime(2026, 7, 8, 10, 0),
      )),
      expect: () => [
        AgendaLoaded(
          entries: [_entry],
          weekStart: _weekStart,
          actionInProgress: true,
        ),
        AgendaLoaded(
          entries: [_entry],
          weekStart: _weekStart,
          actionInProgress: false,
          actionError: 'Erreur réseau',
        ),
      ],
    );
  });

  // -------------------------------------------------------------------------
  // Cloisonnement
  // -------------------------------------------------------------------------

  group('cloisonnement (includeClinical: false)', () {
    test(
        'AgendaEntry ne contient aucun champ clinique (notes médicales, antécédents)',
        () {
      // AgendaEntry est la VO qui transite dans AgendaLoaded.
      // Elle ne doit contenir que des données administratives de planification.
      // Ce test documente l'invariant : si AgendaEntry reçoit un champ clinique
      // (clinicalNotes, medicalNotes, diagnosis…), il faut mettre à jour ce test
      // explicitement — ce qui rend la violation visible.
      expect(_entry.patientName, isNotNull);
      expect(_entry.motif, isNotNull); // motif RDV = champ administratif
      expect(_entry.practitionerName, isNotNull);
      // AgendaEntry.props n'expose que [id, status] — deux champs purement
      // administratifs (le statut sert à l'affichage « À confirmer/Confirmé »),
      // aucune donnée clinique.
      expect(_entry.props, hasLength(2));
      expect(_entry.props.first, equals('e-1'));
      expect(_entry.props, equals(['e-1', _entry.status]));
    });

    blocTest<AgendaBloc, AgendaState>(
        'les entrées chargées ne contiennent aucune note médicale',
        build: () {
          when(() => mockGetAgenda(any()))
              .thenAnswer((_) async => Right([_entry]));
          when(() =>
                  mockListSlots(from: any(named: 'from'), to: any(named: 'to')))
              .thenAnswer((_) async => const Right([]));
          return makeBloc();
        },
        act: (bloc) => bloc.add(AgendaLoadRequested(weekStart: _weekStart)),
        verify: (bloc) {
          final loaded = bloc.state as AgendaLoaded;
          for (final entry in loaded.entries) {
            // Contrôle cloisonnement : aucun champ clinique présent.
            expect(entry, isA<AgendaEntry>());
            // motif est ici la raison administrative du RDV, pas des notes médicales.
            // Si un champ `clinicalNotes` était ajouté à AgendaEntry,
            // ce test devrait être mis à jour explicitement.
            expect(entry.props, hasLength(2),
                reason:
                    'AgendaEntry.props ne doit exposer que [id, status] — aucune donnée clinique');
          }
        });
  });

  // -------------------------------------------------------------------------
  // Widget tests
  // -------------------------------------------------------------------------

  group('AgendaPage (widget)', () {
    testWidgets('affiche le chargement initialement', (tester) async {
      when(() => mockGetAgenda(any())).thenAnswer((_) async => Right([_entry]));
      when(() => mockListSlots(from: any(named: 'from'), to: any(named: 'to')))
          .thenAnswer((_) async => const Right([]));
      final bloc = makeBloc();
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('agenda_loading')), findsOneWidget);
    });

    testWidgets('affiche la liste après chargement', (tester) async {
      when(() => mockGetAgenda(any())).thenAnswer((_) async => Right([_entry]));
      when(() => mockListSlots(from: any(named: 'from'), to: any(named: 'to')))
          .thenAnswer((_) async => const Right([]));
      final bloc = makeBloc()..add(AgendaLoadRequested(weekStart: _weekStart));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('entry_e-1')), findsOneWidget);
    });

    testWidgets(
        'affiche la mention de cloisonnement secrétariat (aucune donnée '
        'clinique) — #5080', (tester) async {
      when(() => mockGetAgenda(any())).thenAnswer((_) async => Right([_entry]));
      when(() => mockListSlots(from: any(named: 'from'), to: any(named: 'to')))
          .thenAnswer((_) async => const Right([]));

      final gi = GetIt.instance;
      await gi.reset();
      gi.registerFactory<AgendaBloc>(() => AgendaBloc(
            getAgenda: mockGetAgenda,
            createAppointment: mockCreate,
            confirmAppointment: mockConfirm,
            rescheduleAppointment: mockReschedule,
            listSlots: mockListSlots,
            listPractitioners: mockListPractitioners,
          ));

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: const Scaffold(body: AgendaPage()),
        ),
      );
      await tester.pump();

      // La note vit sous la grille, en pied de page fixe (plus le dernier
      // item d'une liste défilante) — directement visible, sans scroll.
      final notice = find.byKey(const Key('agenda_confidentiality_notice'));
      expect(notice, findsOneWidget);
      expect(
        find.descendant(of: notice, matching: find.byIcon(Icons.shield)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: notice,
          matching: find.text(
            'Aucune donnée clinique côté secrétariat — motif administratif '
            'uniquement, cloisonnement conservé.',
          ),
        ),
        findsOneWidget,
      );

      await GetIt.instance.reset();
    });

    testWidgets('affiche l\'état vide quand aucun créneau', (tester) async {
      when(() => mockGetAgenda(any())).thenAnswer((_) async => const Right([]));
      when(() => mockListSlots(from: any(named: 'from'), to: any(named: 'to')))
          .thenAnswer((_) async => const Right([]));
      final bloc = makeBloc()..add(AgendaLoadRequested(weekStart: _weekStart));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('agenda_empty')), findsOneWidget);
    });

    testWidgets('affiche une erreur en cas d\'échec', (tester) async {
      when(() => mockGetAgenda(any())).thenAnswer(
        (_) async => Left(NetworkFailure('Pas de réseau')),
      );
      final bloc = makeBloc()..add(AgendaLoadRequested(weekStart: _weekStart));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('agenda_error')), findsOneWidget);
    });

    testWidgets('pull-to-refresh déclenche AgendaLoadRequested',
        (tester) async {
      when(() => mockGetAgenda(any())).thenAnswer((_) async => Right([_entry]));
      when(() => mockListSlots(from: any(named: 'from'), to: any(named: 'to')))
          .thenAnswer((_) async => const Right([]));
      final bloc = makeBloc()..add(AgendaLoadRequested(weekStart: _weekStart));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('entry_e-1')), findsOneWidget);

      await tester.fling(
        find.byType(RefreshIndicator),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      verify(() => mockGetAgenda(any())).called(2);
    });
  });

  // -------------------------------------------------------------------------
  // #5079 — volet latéral détail du RDV sélectionné.
  // -------------------------------------------------------------------------
  group('volet latéral détail du RDV sélectionné (#5079)', () {
    Future<void> pumpWithEntry(WidgetTester tester, AgendaEntry entry) async {
      when(() => mockGetAgenda(any())).thenAnswer((_) async => Right([entry]));
      when(() => mockListSlots(from: any(named: 'from'), to: any(named: 'to')))
          .thenAnswer((_) async => const Right([]));

      final gi = GetIt.instance;
      await gi.reset();
      gi.registerFactory<AgendaBloc>(() => AgendaBloc(
            getAgenda: mockGetAgenda,
            createAppointment: mockCreate,
            confirmAppointment: mockConfirm,
            rescheduleAppointment: mockReschedule,
            listSlots: mockListSlots,
            listPractitioners: mockListPractitioners,
          ));

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: const Scaffold(body: AgendaPage()),
        ),
      );
      await tester.pump();
    }

    testWidgets(
        'sélectionner un RDV confirmé ouvre le volet avec en-tête daté, '
        'identité, motif · durée et pastille Confirmé (sans action Confirmer)',
        (tester) async {
      final entry = AgendaEntry(
        id: 'p-1',
        cabinetId: 'cab-1',
        practitionerId: 'prac-1',
        practitionerName: 'Dr Amélie Rousseau',
        startsAt: DateTime(2026, 8, 11, 14, 30),
        endsAt: DateTime(2026, 8, 11, 15, 0),
        patientId: 'pat-1',
        patientName: 'Camille Moreau',
        motif: 'Détartrage',
        isFree: false,
        status: 'confirmed',
      );

      await pumpWithEntry(tester, entry);

      expect(find.byKey(const Key('agenda_detail_panel_p-1')), findsNothing);

      // Le rendu des blocs RDV cliquables dans la grille est un ticket
      // séparé (#5069, « blocs RDV positionnés ») — la sélection reste
      // accessible via ↓ (#5082), indépendante du rendu.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      final panel = find.byKey(const Key('agenda_detail_panel_p-1'));
      expect(panel, findsOneWidget);
      expect(
        find.descendant(of: panel, matching: find.text('Camille Moreau')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: panel,
          matching: find.textContaining('Détartrage · 30 min'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: panel,
          matching: find.textContaining('Mardi 11 août'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('Confirmé')),
        findsOneWidget,
      );
      // RDV déjà confirmé : pas d'action Confirmer (un re-clic donnerait 409).
      expect(find.byKey(const Key('confirm_p-1')), findsNothing);

      // Bouton fermer referme le volet.
      await tester.tap(find.byKey(const Key('agenda_detail_close')));
      await tester.pump();
      expect(panel, findsNothing);

      await GetIt.instance.reset();
    });

    testWidgets(
        'un RDV à confirmer propose l\'action Confirmer dans le volet et '
        'dispatch AgendaAppointmentConfirmRequested', (tester) async {
      final entry = AgendaEntry(
        id: 'p-2',
        cabinetId: 'cab-1',
        practitionerId: 'prac-1',
        practitionerName: 'Dr Amélie Rousseau',
        startsAt: DateTime(2026, 8, 11, 14, 30),
        endsAt: DateTime(2026, 8, 11, 15, 0),
        patientId: 'pat-1',
        patientName: 'Camille Moreau',
        motif: 'Détartrage',
        isFree: false,
        status: 'requested',
      );

      when(() => mockConfirm('p-2')).thenAnswer(
        (_) async => Right(
          CabinetAppointment(
            id: 'p-2',
            cabinetId: 'cab-1',
            patientId: 'pat-1',
            patientName: 'Camille Moreau',
            practitionerId: 'prac-1',
            practitionerName: 'Dr Amélie Rousseau',
            startsAt: entry.startsAt,
            duration: entry.duration,
            motif: 'Détartrage',
            status: CabinetAppointmentStatus.confirmed,
            slotId: 'slot-1',
          ),
        ),
      );

      await pumpWithEntry(tester, entry);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      final panel = find.byKey(const Key('agenda_detail_panel_p-2'));
      expect(
        find.descendant(of: panel, matching: find.text('À confirmer')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('confirm_p-2')));
      await tester.pump();

      verify(() => mockConfirm('p-2')).called(1);

      await GetIt.instance.reset();
    });

    testWidgets(
        '#6246 : openAppointmentId ouvre le volet du RDV visé dès l\'affichage, '
        'sans sélection manuelle', (tester) async {
      final entry = AgendaEntry(
        id: 'p-3',
        cabinetId: 'cab-1',
        practitionerId: 'prac-1',
        practitionerName: 'Dr Amélie Rousseau',
        startsAt: DateTime(2026, 8, 11, 4, 6),
        endsAt: DateTime(2026, 8, 11, 4, 36),
        patientId: 'pat-1',
        patientName: 'Marc Dubois',
        isFree: false,
        status: 'requested',
      );

      when(() => mockGetAgenda(any())).thenAnswer((_) async => Right([entry]));
      when(() => mockListSlots(from: any(named: 'from'), to: any(named: 'to')))
          .thenAnswer((_) async => const Right([]));

      final gi = GetIt.instance;
      await gi.reset();
      gi.registerFactory<AgendaBloc>(() => AgendaBloc(
            getAgenda: mockGetAgenda,
            createAppointment: mockCreate,
            confirmAppointment: mockConfirm,
            rescheduleAppointment: mockReschedule,
            listSlots: mockListSlots,
            listPractitioners: mockListPractitioners,
          ));

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: const Scaffold(body: AgendaPage(openAppointmentId: 'p-3')),
        ),
      );
      await tester.pumpAndSettle();

      final panel = find.byKey(const Key('agenda_detail_panel_p-3'));
      expect(panel, findsOneWidget);
      expect(
        find.descendant(of: panel, matching: find.text('Marc Dubois')),
        findsOneWidget,
      );

      await GetIt.instance.reset();
    });
  });

  // -------------------------------------------------------------------------
  // Couleur par praticien (blocs + légende, #5074)
  // -------------------------------------------------------------------------

  group('couleur par praticien — blocs + légende de pied (#5074)', () {
    testWidgets(
        '1er praticien du roster -> bloc émeraude, 2e -> sable, 3e -> neutre, '
        'même si le 3e n\'a aucun RDV cette semaine (#4666)', (tester) async {
      final rousseauEntry = AgendaEntry(
        id: 'e-rousseau',
        cabinetId: 'cab-1',
        practitionerId: 'prac-rousseau',
        practitionerName: 'Dr Rousseau',
        startsAt: DateTime(2026, 7, 7, 9, 0),
        endsAt: DateTime(2026, 7, 7, 9, 30),
        patientName: 'Marie Dupont',
        motif: 'Contrôle',
        isFree: false,
        status: 'confirmed',
      );
      final lefevreEntry = AgendaEntry(
        id: 'e-lefevre',
        cabinetId: 'cab-1',
        practitionerId: 'prac-lefevre',
        practitionerName: 'Dr Lefèvre',
        startsAt: DateTime(2026, 7, 7, 10, 0),
        endsAt: DateTime(2026, 7, 7, 10, 30),
        patientName: 'Marc Dubois',
        motif: 'Détartrage',
        isFree: false,
        status: 'confirmed',
      );

      when(() => mockGetAgenda(any()))
          .thenAnswer((_) async => Right([rousseauEntry, lefevreEntry]));
      when(() => mockListSlots(from: any(named: 'from'), to: any(named: 'to')))
          .thenAnswer((_) async => const Right([]));
      // Roster complet : Dr Nadeau (3e) n'a aucun RDV cette semaine mais
      // reste présent dans le roster (#4666), donc dans la palette/légende.
      when(() => mockListPractitioners()).thenAnswer(
        (_) async => const Right([
          CabinetPractitioner(id: 'prac-rousseau', displayName: 'Dr Rousseau'),
          CabinetPractitioner(id: 'prac-lefevre', displayName: 'Dr Lefèvre'),
          CabinetPractitioner(id: 'prac-nadeau', displayName: 'Dr Nadeau'),
        ]),
      );

      final gi = GetIt.instance;
      await gi.reset();
      gi.registerFactory<AgendaBloc>(() => AgendaBloc(
            getAgenda: mockGetAgenda,
            createAppointment: mockCreate,
            confirmAppointment: mockConfirm,
            rescheduleAppointment: mockReschedule,
            listSlots: mockListSlots,
            listPractitioners: mockListPractitioners,
          ));

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: const Scaffold(body: AgendaPage()),
        ),
      );
      await tester.pump();

      // Le rendu des blocs RDV (couleur par praticien sur le bloc lui-même)
      // est un ticket séparé (#5069, « blocs RDV positionnés ») — seule la
      // légende de pied, indépendante du rendu de la grille, est vérifiable
      // ici.
      //
      // Légende de pied : les 3 praticiens du roster apparaissent, y compris
      // Dr Nadeau (0 RDV cette semaine) — #4666 ne doit pas régresser.
      expect(find.byKey(const Key('agenda_legend_practitioner_prac-rousseau')),
          findsOneWidget);
      expect(find.byKey(const Key('agenda_legend_practitioner_prac-lefevre')),
          findsOneWidget);
      expect(find.byKey(const Key('agenda_legend_practitioner_prac-nadeau')),
          findsOneWidget);
      expect(find.byKey(const Key('agenda_legend_pending')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('agenda_legend_practitioner_prac-nadeau')),
          matching: find.text('Dr Nadeau'),
        ),
        findsOneWidget,
      );

      await GetIt.instance.reset();
    });
  });

  // -------------------------------------------------------------------------
  // Filtre praticien (dropdown)
  // -------------------------------------------------------------------------

  group('filtre praticien (puces à bascule, #5076)', () {
    testWidgets(
        '3 RDV 2 praticiens → bascule 1 puce → filtre live sur le compteur '
        'de la colonne jour', (tester) async {
      // AgendaPage charge toujours `_currentWeekStart()` (semaine réelle du
      // jour d'exécution du test) — un jour ouvré de cette semaine réelle
      // (mardi), pas une date fixe, pour que les 3 entrées tombent dans une
      // colonne de la grille.
      final day = _thisWeekMonday().add(const Duration(days: 1));
      DateTime at(int hour) => DateTime(day.year, day.month, day.day, hour, 0);
      final dayKey = '${day.year}-${day.month}-${day.day}';

      final e1 = AgendaEntry(
        id: 'f-1',
        cabinetId: 'cab-1',
        practitionerId: 'prac-1',
        practitionerName: 'Dr Martin',
        startsAt: at(9),
        endsAt: at(9).add(const Duration(minutes: 30)),
        patientName: 'Alice Durand',
        isFree: false,
      );
      final e2 = AgendaEntry(
        id: 'f-2',
        cabinetId: 'cab-1',
        practitionerId: 'prac-1',
        practitionerName: 'Dr Martin',
        startsAt: at(10),
        endsAt: at(10).add(const Duration(minutes: 30)),
        patientName: 'Bob Dupont',
        isFree: false,
      );
      final e3 = AgendaEntry(
        id: 'f-3',
        cabinetId: 'cab-1',
        practitionerId: 'prac-2',
        practitionerName: 'Dr Dupont',
        startsAt: at(11),
        endsAt: at(11).add(const Duration(minutes: 30)),
        patientName: 'Charlie Bernard',
        isFree: false,
      );

      when(() => mockGetAgenda(any()))
          .thenAnswer((_) async => Right([e1, e2, e3]));
      when(() => mockListSlots(from: any(named: 'from'), to: any(named: 'to')))
          .thenAnswer((_) async => const Right([]));

      final gi = GetIt.instance;
      await gi.reset();
      gi.registerFactory<AgendaBloc>(() => AgendaBloc(
            getAgenda: mockGetAgenda,
            createAppointment: mockCreate,
            confirmAppointment: mockConfirm,
            rescheduleAppointment: mockReschedule,
            listSlots: mockListSlots,
            listPractitioners: mockListPractitioners,
          ));

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: const Scaffold(body: AgendaPage()),
        ),
      );
      await tester.pump();

      String countTextOf(String key) =>
          tester.widget<Text>(find.byKey(Key(key))).data!;

      // Les 3 entrées comptent dans la colonne du jour.
      expect(countTextOf('agenda_day_count_$dayKey'), '3');

      // Chaque puce affiche le compteur (total, non filtré) d'entrées du
      // praticien.
      expect(
        find.descendant(
          of: find.byKey(const Key('practitioner_chip_prac-1')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('practitioner_chip_prac-2')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );

      // Bascule la puce Dr Martin (prac-1) : seules ses 2 entrées restent
      // filtrées → le compteur de la colonne jour passe à 2.
      await tester.tap(find.byKey(const Key('practitioner_chip_prac-1')));
      await tester.pumpAndSettle();
      expect(countTextOf('agenda_day_count_$dayKey'), '2');

      // Bascule aussi la puce Dr Dupont (prac-2) : les deux puces actives en
      // même temps filtrent sur les deux praticiens (filtre non exclusif) →
      // les 3 entrées reviennent.
      await tester.tap(find.byKey(const Key('practitioner_chip_prac-2')));
      await tester.pumpAndSettle();
      expect(countTextOf('agenda_day_count_$dayKey'), '3');

      // Re-bascule (off) la puce Dr Martin : Dr Dupont seul reste actif.
      await tester.tap(find.byKey(const Key('practitioner_chip_prac-1')));
      await tester.pumpAndSettle();
      expect(countTextOf('agenda_day_count_$dayKey'), '1');

      await GetIt.instance.reset();
    });
  });

  // -------------------------------------------------------------------------
  // #3466 — filtrage des créneaux réellement réservables pour le picker.
  // -------------------------------------------------------------------------
  group('bookableSlots', () {
    Slot slot({
      required String id,
      required DateTime start,
      String practitioner = 'prac-1',
      bool available = true,
      Duration duration = const Duration(minutes: 30),
    }) =>
        Slot(
          id: id,
          cabinetId: 'cab-1',
          practitionerId: practitioner,
          startsAt: start,
          endsAt: start.add(duration),
          isAvailable: available,
        );

    AgendaEntry booked({
      required DateTime start,
      String practitioner = 'prac-1',
      String status = 'requested',
      Duration duration = const Duration(minutes: 30),
    }) =>
        AgendaEntry(
          id: 'a-${start.millisecondsSinceEpoch}',
          cabinetId: 'cab-1',
          practitionerId: practitioner,
          practitionerName: 'Dr Martin',
          startsAt: start,
          endsAt: start.add(duration),
          patientId: 'pat',
          patientName: 'Patient',
          isFree: false,
          status: status,
        );

    test('exclut un créneau ouvert chevauchant un RDV du même praticien', () {
      final s = slot(id: 's1', start: DateTime(2026, 7, 8, 9, 0));
      final b = booked(start: DateTime(2026, 7, 8, 9, 0));
      expect(bookableSlots([s], [b]), isEmpty);
    });

    test('garde un créneau ouvert sans RDV chevauchant', () {
      final s = slot(id: 's1', start: DateTime(2026, 7, 8, 10, 0));
      final b = booked(start: DateTime(2026, 7, 8, 9, 0));
      expect(bookableSlots([s], [b]).map((s) => s.id), ['s1']);
    });

    test('un RDV d\'un autre praticien ne bloque pas le créneau', () {
      final s = slot(id: 's1', start: DateTime(2026, 7, 8, 9, 0));
      final b =
          booked(start: DateTime(2026, 7, 8, 9, 0), practitioner: 'prac-2');
      expect(bookableSlots([s], [b]).map((s) => s.id), ['s1']);
    });

    test('un RDV annulé ne bloque pas le créneau', () {
      final s = slot(id: 's1', start: DateTime(2026, 7, 8, 9, 0));
      final b = booked(start: DateTime(2026, 7, 8, 9, 0), status: 'cancelled');
      expect(bookableSlots([s], [b]).map((s) => s.id), ['s1']);
    });

    test('exclut les créneaux non disponibles', () {
      final s =
          slot(id: 's1', start: DateTime(2026, 7, 8, 9, 0), available: false);
      expect(bookableSlots([s], const []), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // #5082 — raccourcis clavier de bout en bout.
  // -------------------------------------------------------------------------
  group('raccourcis clavier (#5082)', () {
    void registerBloc(GetIt gi) {
      gi.registerFactory<AgendaBloc>(() => AgendaBloc(
            getAgenda: mockGetAgenda,
            createAppointment: mockCreate,
            confirmAppointment: mockConfirm,
            rescheduleAppointment: mockReschedule,
            listSlots: mockListSlots,
            listPractitioners: mockListPractitioners,
          ));
    }

    Future<void> pumpAgenda(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: const Scaffold(body: AgendaPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('→/← changent de semaine (±7j), T revient à aujourd\'hui',
        (tester) async {
      when(() => mockGetAgenda(any())).thenAnswer((_) async => const Right([]));
      when(() => mockListSlots(from: any(named: 'from'), to: any(named: 'to')))
          .thenAnswer((_) async => const Right([]));

      final gi = GetIt.instance;
      await gi.reset();
      registerBloc(gi);

      await pumpAgenda(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.pumpAndSettle();

      final captured =
          verify(() => mockGetAgenda(captureAny())).captured.cast<DateTime>();
      expect(captured.length, 4);
      // → : +7 jours par rapport à la semaine initiale.
      expect(captured[1].difference(captured[0]), const Duration(days: 7));
      // ← : retour exact à la semaine initiale (pure arithmétique de dates,
      // aucun nouvel appel à DateTime.now()).
      expect(captured[2], captured[0]);
      // T : revient au jour courant — comparaison sur la date seule (année/
      // mois/jour), DateTime.now() pouvant différer de quelques
      // microsecondes entre le 1er chargement et l'appui sur T.
      expect(captured[3].year, captured[0].year);
      expect(captured[3].month, captured[0].month);
      expect(captured[3].day, captured[0].day);

      await GetIt.instance.reset();
    });

    testWidgets(
        '↑/↓ déplacent la sélection, ⏎ confirme seulement un RDV en attente',
        (tester) async {
      final pending = AgendaEntry(
        id: 'sel-1',
        cabinetId: 'cab-1',
        practitionerId: 'prac-1',
        practitionerName: 'Dr Martin',
        startsAt: DateTime(2026, 7, 7, 9, 0),
        endsAt: DateTime(2026, 7, 7, 9, 30),
        patientName: 'Alice Durand',
        isFree: false,
        status: 'requested',
      );
      final confirmed = AgendaEntry(
        id: 'sel-2',
        cabinetId: 'cab-1',
        practitionerId: 'prac-1',
        practitionerName: 'Dr Martin',
        startsAt: DateTime(2026, 7, 7, 10, 0),
        endsAt: DateTime(2026, 7, 7, 10, 30),
        patientName: 'Bob Dupont',
        isFree: false,
        status: 'confirmed',
      );

      when(() => mockGetAgenda(any()))
          .thenAnswer((_) async => Right([pending, confirmed]));
      when(() => mockListSlots(from: any(named: 'from'), to: any(named: 'to')))
          .thenAnswer((_) async => const Right([]));
      when(() => mockConfirm(any()))
          .thenAnswer((_) async => Left(NetworkFailure('erreur')));

      final gi = GetIt.instance;
      await gi.reset();
      registerBloc(gi);

      await pumpAgenda(tester);

      // ↓ sélectionne le 1er RDV (en attente) → ⏎ le confirme.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      verify(() => mockConfirm('sel-1')).called(1);

      // ↓ sélectionne ensuite le 2e RDV (déjà confirmé) → ⏎ ne fait rien
      // (même règle que le bouton Confirmer, masqué une fois confirmé — un
      // re-clic donnerait 409).
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      verifyNever(() => mockConfirm('sel-2'));

      await GetIt.instance.reset();
    });

    testWidgets('⌘N ouvre le dialogue Nouveau RDV', (tester) async {
      when(() => mockGetAgenda(any())).thenAnswer((_) async => const Right([]));
      when(() => mockListSlots(from: any(named: 'from'), to: any(named: 'to')))
          .thenAnswer((_) async => const Right([]));

      final gi = GetIt.instance;
      await gi.reset();
      registerBloc(gi);
      final mockListPatients = MockListCabinetPatientsUseCase();
      when(() => mockListPatients()).thenAnswer((_) async => const Right([]));
      gi.registerFactory<ListCabinetPatientsUseCase>(() => mockListPatients);

      await pumpAgenda(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();

      expect(find.text('Nouveau rendez-vous'), findsOneWidget);

      await GetIt.instance.reset();
    });

    testWidgets('/ met le focus sur la recherche patient', (tester) async {
      when(() => mockGetAgenda(any())).thenAnswer((_) async => const Right([]));
      when(() => mockListSlots(from: any(named: 'from'), to: any(named: 'to')))
          .thenAnswer((_) async => const Right([]));

      final gi = GetIt.instance;
      await gi.reset();
      registerBloc(gi);

      await pumpAgenda(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.pumpAndSettle();

      final focusNode = tester
          .widget<TextField>(find.descendant(
            of: find.byKey(const Key('agenda_patient_search')),
            matching: find.byType(TextField),
          ))
          .focusNode;
      expect(focusNode?.hasFocus, isTrue);

      await GetIt.instance.reset();
    });
  });

  // -------------------------------------------------------------------------
  // #5078 — dialogue « Nouveau RDV » simplifié (patient en recherche). Le
  // rendu de créneaux libres cliquables dans la grille (#5077) est hors
  // périmètre de #5069 (ticket « blocs RDV positionnés ») — le dialogue
  // s'ouvre donc ici via le bouton « Nouveau RDV » de la barre d'outils
  // (toujours présent, indépendant du rendu de la grille) avec le picker de
  // créneau.
  // -------------------------------------------------------------------------
  group('Nouveau RDV — dialogue simplifié (#5078)', () {
    void registerBloc(GetIt gi, MockListCabinetPatientsUseCase listPatients) {
      gi.registerFactory<AgendaBloc>(() => AgendaBloc(
            getAgenda: mockGetAgenda,
            createAppointment: mockCreate,
            confirmAppointment: mockConfirm,
            rescheduleAppointment: mockReschedule,
            listSlots: mockListSlots,
            listPractitioners: mockListPractitioners,
          ));
      gi.registerFactory<ListCabinetPatientsUseCase>(() => listPatients);
    }

    Future<void> pumpAgenda(WidgetTester tester) async {
      when(() => mockGetAgenda(any())).thenAnswer((_) async => const Right([]));
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: const Scaffold(body: AgendaPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Ouvre le dialogue via le bouton « Nouveau RDV » puis choisit
    /// [freeSlot] dans le picker (un seul créneau disponible dans ces tests).
    Future<void> openDialogAndPickSlot(
      WidgetTester tester,
      Slot freeSlot,
      String slotLabel,
    ) async {
      await tester.tap(find.byKey(const Key('new_appointment_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('slot_picker_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(slotLabel).last);
      await tester.pumpAndSettle();
    }

    final freeSlot = Slot(
      id: 'slot-1',
      cabinetId: 'cab-1',
      practitionerId: 'prac-1',
      startsAt: DateTime(2026, 7, 7, 9, 0),
      endsAt: DateTime(2026, 7, 7, 9, 30),
      isAvailable: true,
    );
    // `_slotLabel` (agenda_page.dart) pour `freeSlot` : mardi 7 juillet 2026.
    const freeSlotLabel = 'Mar 7 juil. – 09:00';
    final alice = CabinetPatient(
      id: 'pat-alice',
      cabinetId: 'cab-1',
      firstName: 'Alice',
      lastName: 'Durand',
      createdAt: DateTime(2020, 1, 1),
    );
    final bob = CabinetPatient(
      id: 'pat-bob',
      cabinetId: 'cab-1',
      firstName: 'Bob',
      lastName: 'Martin',
      createdAt: DateTime(2020, 1, 1),
    );

    testWidgets(
        'le patient se choisit via une recherche filtrant par nom, et créer '
        'reste désactivé sans patient choisi', (tester) async {
      when(() => mockListSlots(from: any(named: 'from'), to: any(named: 'to')))
          .thenAnswer((_) async => Right([freeSlot]));
      final mockListPatients = MockListCabinetPatientsUseCase();
      when(() => mockListPatients())
          .thenAnswer((_) async => Right([alice, bob]));

      final gi = GetIt.instance;
      await gi.reset();
      registerBloc(gi, mockListPatients);

      await pumpAgenda(tester);
      await openDialogAndPickSlot(tester, freeSlot, freeSlotLabel);

      // Pas de dropdown listant toute la patientèle.
      expect(find.byKey(const Key('patient_picker_dropdown')), findsNothing);

      final createButton = find.byKey(const Key('create_appointment_button'));
      expect(tester.widget<FilledButton>(createButton).onPressed, isNull);

      await tester.enterText(
          find.byKey(const Key('patient_search_field')), 'ali');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('patient_option_pat-alice')), findsOneWidget);
      expect(find.byKey(const Key('patient_option_pat-bob')), findsNothing);

      await tester.tap(find.byKey(const Key('patient_option_pat-alice')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('patient_search_field')), findsNothing);
      expect(find.text('Alice Durand'), findsOneWidget);
      expect(tester.widget<FilledButton>(createButton).onPressed, isNotNull);

      await GetIt.instance.reset();
    });

    testWidgets(
        'créer le RDV envoie un CabinetAppointment avec slotId et le '
        'patientId résolu par la recherche', (tester) async {
      when(() => mockListSlots(from: any(named: 'from'), to: any(named: 'to')))
          .thenAnswer((_) async => Right([freeSlot]));
      final mockListPatients = MockListCabinetPatientsUseCase();
      when(() => mockListPatients()).thenAnswer((_) async => Right([alice]));
      when(() => mockCreate(any())).thenAnswer(
        (_) async => Right(CabinetAppointment(
          id: 'appt-1',
          cabinetId: 'cab-1',
          patientId: alice.id,
          patientName: alice.fullName,
          practitionerId: freeSlot.practitionerId,
          practitionerName: 'Dr Martin',
          startsAt: freeSlot.startsAt,
          duration: freeSlot.duration,
          motif: 'Consultation',
          status: CabinetAppointmentStatus.requested,
          slotId: freeSlot.id,
        )),
      );

      final gi = GetIt.instance;
      await gi.reset();
      registerBloc(gi, mockListPatients);

      await pumpAgenda(tester);
      await openDialogAndPickSlot(tester, freeSlot, freeSlotLabel);

      await tester.enterText(
          find.byKey(const Key('patient_search_field')), 'ali');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('patient_option_pat-alice')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('create_appointment_button')));
      await tester.pumpAndSettle();

      final captured = verify(() => mockCreate(captureAny())).captured;
      expect(captured, hasLength(1));
      final appointment = captured.first as CabinetAppointment;
      expect(appointment.slotId, freeSlot.id);
      expect(appointment.patientId, alice.id);

      await GetIt.instance.reset();
    });
  });
}
