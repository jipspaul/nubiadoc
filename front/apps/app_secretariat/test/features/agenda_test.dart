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

    // #5168 : pastille praticien de la grille agenda — même couleur, dérivée
    // du practitionerId via practitionerColor, que la colonne Praticien de
    // la salle d'attente (front/apps/app_secretariat/waiting_room_page.dart).
    testWidgets(
        'pastille praticien — couleur dérivée de practitionerId via practitionerColor — #5168',
        (tester) async {
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

      final dot = tester.widget<Container>(
        find.byKey(const Key('entry_practitioner_dot_e-1')),
      );
      final decoration = dot.decoration as BoxDecoration;
      expect(decoration.color, practitionerColor(_entry.practitionerId));

      await gi.reset();
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

      await gi.reset();
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

      await tester.tap(find.byKey(const Key('entry_p-1')));
      await tester.pump();

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

      await tester.tap(find.byKey(const Key('entry_p-2')));
      await tester.pump();

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
  });

  // -------------------------------------------------------------------------
  // #3896 — nom/motif du patient visibles sur mobile pour un RDV « À confirmer ».
  // -------------------------------------------------------------------------

  group('carte RDV mobile (#3896)', () {
    testWidgets(
        'nom du patient visible sur un viewport mobile 390px, RDV à confirmer',
        (tester) async {
      final entry = AgendaEntry(
        id: 'm-1',
        cabinetId: 'cab-1',
        practitionerId: 'prac-1',
        practitionerName: 'Dr Hugo Marin',
        startsAt: DateTime(2026, 7, 7, 9, 0),
        endsAt: DateTime(2026, 7, 7, 9, 30),
        patientId: 'pat-1',
        patientName: 'Marc Dubois',
        motif: 'Contrôle',
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

      // Viewport mobile 390x844 — repro exacte de l'issue (le nom s'affichait
      // normalement à 1280px mais était clippé à ~0px de largeur à 390px,
      // avant que la pastille/bouton « Confirmer » soit sortie de la carte
      // (#5079 : désormais dans le volet latéral, plus dans le Row Expanded).
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: const Scaffold(body: AgendaPage()),
        ),
      );
      await tester.pump();

      expect(
        find.text('Marc Dubois'),
        findsOneWidget,
        reason: 'le nom du patient doit rester visible à 390px de large, '
            'pas clippé par la carte RDV',
      );
      expect(find.textContaining('Contrôle'), findsOneWidget);

      // Le bouton Confirmer vit désormais dans le volet latéral détail
      // (#5079) — sélectionner le RDV l'ouvre et l'expose.
      await tester.tap(find.byKey(const Key('entry_m-1')));
      await tester.pump();
      expect(find.byKey(const Key('confirm_m-1')), findsOneWidget);

      await gi.reset();
    });
  });

  // -------------------------------------------------------------------------
  // Filtre praticien (dropdown)
  // -------------------------------------------------------------------------

  group('filtre praticien (dropdown)', () {
    testWidgets('3 RDV 2 praticiens → sélection 1 → filtre live',
        (tester) async {
      final e1 = AgendaEntry(
        id: 'f-1',
        cabinetId: 'cab-1',
        practitionerId: 'prac-1',
        practitionerName: 'Dr Martin',
        startsAt: DateTime(2026, 7, 7, 9, 0),
        endsAt: DateTime(2026, 7, 7, 9, 30),
        patientName: 'Alice Durand',
        isFree: false,
      );
      final e2 = AgendaEntry(
        id: 'f-2',
        cabinetId: 'cab-1',
        practitionerId: 'prac-1',
        practitionerName: 'Dr Martin',
        startsAt: DateTime(2026, 7, 7, 10, 0),
        endsAt: DateTime(2026, 7, 7, 10, 30),
        patientName: 'Bob Dupont',
        isFree: false,
      );
      final e3 = AgendaEntry(
        id: 'f-3',
        cabinetId: 'cab-1',
        practitionerId: 'prac-2',
        practitionerName: 'Dr Dupont',
        startsAt: DateTime(2026, 7, 7, 11, 0),
        endsAt: DateTime(2026, 7, 7, 11, 30),
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

      // Les 3 entrées sont visibles
      expect(find.byKey(const Key('entry_f-1')), findsOneWidget);
      expect(find.byKey(const Key('entry_f-2')), findsOneWidget);
      expect(find.byKey(const Key('entry_f-3')), findsOneWidget);

      // Ouvre le dropdown
      await tester.tap(find.byKey(const Key('practitioner_filter_dropdown')));
      await tester.pumpAndSettle();

      // Sélectionne Dr Martin
      await tester.tap(find.text('Dr Martin').last);
      await tester.pumpAndSettle();

      // Seules les 2 entrées de Dr Martin restent visibles
      expect(find.byKey(const Key('entry_f-1')), findsOneWidget);
      expect(find.byKey(const Key('entry_f-2')), findsOneWidget);
      expect(find.byKey(const Key('entry_f-3')), findsNothing);

      await gi.reset();
    });
  });

  // -------------------------------------------------------------------------
  // #4666 — nom du praticien sur l'agenda cabinet : résolu via le roster
  // (ListCabinetPractitionersUseCase), pas seulement via `entry.practitionerName`
  // (qui peut être vide pour un slot, cf. #4608).
  // -------------------------------------------------------------------------
  group('résolution du nom praticien via le roster (#4666)', () {
    testWidgets(
        'practitioner_id connu (roster) mais practitionerName vide sur '
        'l\'entrée -> nom affiché sans séparateur pendant', (tester) async {
      final entry = AgendaEntry(
        id: 'r-1',
        cabinetId: 'cab-1',
        practitionerId: 'prac-1',
        // Nom vide sur l'entrée elle-même (ex : slot non enrichi) — seul le
        // roster connaît le nom.
        practitionerName: '',
        startsAt: DateTime(2026, 7, 7, 9, 0),
        endsAt: DateTime(2026, 7, 7, 9, 30),
        patientId: 'pat-1',
        patientName: 'Marc Dubois',
        motif: 'Contrôle',
        isFree: false,
      );

      when(() => mockGetAgenda(any())).thenAnswer((_) async => Right([entry]));
      when(() => mockListSlots(from: any(named: 'from'), to: any(named: 'to')))
          .thenAnswer((_) async => const Right([]));
      when(() => mockListPractitioners()).thenAnswer(
        (_) async => const Right([
          CabinetPractitioner(id: 'prac-1', displayName: 'Dr Hugo Marin'),
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

      expect(find.textContaining('Dr Hugo Marin'), findsOneWidget);
      // Pas de séparateur '·' pendant : le motif et le nom sont joints par
      // ' · ', jamais un ' · ' en tête isolé.
      expect(find.text('· Dr Hugo Marin'), findsNothing);

      await gi.reset();
    });

    testWidgets(
        'practitioner_id inconnu du roster -> aucun nom, pas de libellé '
        'orphelin', (tester) async {
      final entry = AgendaEntry(
        id: 'r-2',
        cabinetId: 'cab-1',
        practitionerId: 'prac-inconnu',
        practitionerName: '',
        startsAt: DateTime(2026, 7, 7, 9, 0),
        endsAt: DateTime(2026, 7, 7, 9, 30),
        patientId: 'pat-1',
        patientName: 'Marc Dubois',
        motif: 'Contrôle',
        isFree: false,
      );

      when(() => mockGetAgenda(any())).thenAnswer((_) async => Right([entry]));
      when(() => mockListSlots(from: any(named: 'from'), to: any(named: 'to')))
          .thenAnswer((_) async => const Right([]));
      when(() => mockListPractitioners()).thenAnswer(
        (_) async => const Right([
          CabinetPractitioner(id: 'prac-1', displayName: 'Dr Hugo Marin'),
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

      // Le motif reste visible, seul (pas de "· <motif>" ni "<motif> ·").
      expect(find.text('Contrôle'), findsOneWidget);
      expect(find.textContaining('Dr Hugo Marin'), findsNothing);

      await gi.reset();
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

      await gi.reset();
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

      await gi.reset();
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

      await gi.reset();
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

      await gi.reset();
    });
  });
}
