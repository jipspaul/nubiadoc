import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/bookable_slots/bookable_slots_bloc.dart';
import 'package:app_secretariat/features/bookable_slots/bookable_slots_event.dart';
import 'package:app_secretariat/features/bookable_slots/bookable_slots_page.dart';
import 'package:app_secretariat/features/bookable_slots/bookable_slots_state.dart';
import 'package:app_secretariat/features/bookable_slots/create_slot_dialog.dart';
import 'package:app_secretariat/pro_config.dart';

class _MockSlotsRepository extends Mock implements SlotsRepository {}

class _MockCabinetAgendaRepository extends Mock
    implements CabinetAgendaRepository {}

class _MockBookableSlotsBloc
    extends MockBloc<BookableSlotsEvent, BookableSlotsState>
    implements BookableSlotsBloc {}

final _slot = Slot(
  id: 's1',
  cabinetId: 'c1',
  practitionerId: 'p1',
  startsAt: DateTime(2026, 6, 20, 9, 0),
  endsAt: DateTime(2026, 6, 20, 9, 30),
  isAvailable: true,
);

const _practitioners = [
  CabinetPractitioner(id: 'p1', displayName: 'Dr Alice Martin'),
  CabinetPractitioner(id: 'p2', displayName: 'Dr Bob Durand'),
];

void main() {
  setUpAll(() {
    registerFallbackValue(
      Slot(
        id: '',
        cabinetId: '',
        practitionerId: '',
        startsAt: DateTime(2026),
        endsAt: DateTime(2026),
        isAvailable: true,
      ),
    );
  });

  // --- Cloisonnement invariant --------------------------------------------------
  group('ProConfig — cloisonnement', () {
    test('includeClinical est false', () {
      expect(ProConfig.includeClinical, isFalse);
    });

    test('aucune destination requiresClinical dans shellConfig', () {
      final clinicalDests = ProConfig.shellConfig.destinations
          .where((d) => d.requiresClinical)
          .toList();
      expect(clinicalDests, isEmpty);
    });
  });

  // --- Slot entity : pas de champ clinique ------------------------------------
  group('Slot — cloisonnement champs cliniques', () {
    test('Slot n\'expose que des champs administratifs (pas de motif/notes)',
        () {
      expect(_slot.id, isNotEmpty);
      expect(_slot.startsAt, isNotNull);
      expect(_slot.endsAt, isNotNull);
      expect(_slot.isAvailable, isTrue);
      // Slot n'a pas de champ motif, notes_medicales ni données cliniques —
      // garantie structurelle par le type.
    });
  });

  // --- BookableSlotsBloc -------------------------------------------------------
  group('BookableSlotsBloc', () {
    late _MockSlotsRepository repo;
    late _MockCabinetAgendaRepository agendaRepo;
    late ListBookableSlotsUseCase useCase;
    late CreateSlotUseCase createSlotUseCase;
    late ListCabinetPractitionersUseCase listPractitionersUseCase;

    setUp(() {
      repo = _MockSlotsRepository();
      agendaRepo = _MockCabinetAgendaRepository();
      useCase = ListBookableSlotsUseCase(repo);
      createSlotUseCase = CreateSlotUseCase(repo);
      listPractitionersUseCase = ListCabinetPractitionersUseCase(agendaRepo);
    });

    void stubList(List<Slot> slots) {
      when(
        () => repo.list(
            from: any(named: 'from'),
            to: any(named: 'to'),
            practitionerId: any(named: 'practitionerId')),
      ).thenAnswer((_) async => Right(slots));
    }

    void stubPractitioners(List<CabinetPractitioner> practitioners) {
      when(() => agendaRepo.listPractitioners())
          .thenAnswer((_) async => Right(practitioners));
    }

    BookableSlotsBloc buildBloc() => BookableSlotsBloc(
          listSlots: useCase,
          createSlot: createSlotUseCase,
          listPractitioners: listPractitionersUseCase,
          now: () => DateTime(2026, 6, 1),
        );

    blocTest<BookableSlotsBloc, BookableSlotsState>(
      'émet Loading puis Loaded (avec roster praticiens) sur succès',
      build: () {
        stubList([_slot]);
        stubPractitioners(_practitioners);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const BookableSlotsLoadRequested()),
      expect: () => [
        const BookableSlotsLoading(),
        BookableSlotsLoaded([_slot], practitioners: _practitioners),
      ],
    );

    blocTest<BookableSlotsBloc, BookableSlotsState>(
      'émet Loading puis Error sur échec du chargement des créneaux',
      build: () {
        when(
          () => repo.list(
              from: any(named: 'from'),
              to: any(named: 'to'),
              practitionerId: any(named: 'practitionerId')),
        ).thenAnswer(
          (_) async => Left(const NetworkFailure('Erreur réseau')),
        );
        return buildBloc();
      },
      act: (bloc) => bloc.add(const BookableSlotsLoadRequested()),
      expect: () => [
        const BookableSlotsLoading(),
        const BookableSlotsError('Erreur réseau'),
      ],
    );

    blocTest<BookableSlotsBloc, BookableSlotsState>(
      'échec du roster n\'empêche pas d\'afficher les créneaux',
      build: () {
        stubList([_slot]);
        when(() => agendaRepo.listPractitioners()).thenAnswer(
          (_) async => Left(const ServerFailure(message: 'boom')),
        );
        return buildBloc();
      },
      act: (bloc) => bloc.add(const BookableSlotsLoadRequested()),
      expect: () => [
        const BookableSlotsLoading(),
        BookableSlotsLoaded([_slot]),
      ],
    );

    blocTest<BookableSlotsBloc, BookableSlotsState>(
      'create → envoie un practitioner_id valide puis recharge',
      build: () {
        when(() => repo.create(any())).thenAnswer((_) async => Right(_slot));
        stubList([_slot]);
        stubPractitioners(const []);
        return buildBloc();
      },
      act: (bloc) => bloc.add(CreateSlotRequested(
        practitionerId: 'p1',
        startsAt: DateTime(2026, 6, 20, 9, 0),
        endsAt: DateTime(2026, 6, 20, 9, 30),
      )),
      expect: () => [
        const BookableSlotsLoading(),
        const BookableSlotsSlotCreatedSuccess(),
        const BookableSlotsLoading(),
        BookableSlotsLoaded([_slot]),
      ],
      verify: (_) {
        final captured =
            verify(() => repo.create(captureAny())).captured.single as Slot;
        // #3465 : plus de practitionerId vide — l'ID sélectionné est transmis.
        expect(captured.practitionerId, 'p1');
      },
    );
  });

  // --- sanitizeBookableSlots (issue #3365) ------------------------------------
  group('sanitizeBookableSlots', () {
    final now = DateTime(2026, 7, 4, 12, 0);

    Slot slot({
      required String id,
      required DateTime start,
      Duration duration = const Duration(minutes: 30),
      bool available = true,
      String practitioner = 'p1',
    }) =>
        Slot(
          id: id,
          cabinetId: 'c1',
          practitionerId: practitioner,
          startsAt: start,
          endsAt: start.add(duration),
          isAvailable: available,
        );

    test('masque les créneaux passés (endsAt avant maintenant)', () {
      final past = slot(id: 'past', start: DateTime(2026, 6, 20, 9, 0));
      final future = slot(id: 'future', start: DateTime(2026, 7, 10, 9, 0));
      final result = sanitizeBookableSlots([past, future], now);
      expect(result.map((s) => s.id), ['future']);
    });

    test('supprime les doublons (même praticien + même plage)', () {
      final a = slot(id: 'a', start: DateTime(2026, 7, 10, 9, 0));
      final dup = slot(id: 'b', start: DateTime(2026, 7, 10, 9, 0));
      final result = sanitizeBookableSlots([a, dup], now);
      expect(result.length, 1);
    });

    test('sur un doublon, garde le créneau disponible', () {
      final busy = slot(
          id: 'busy', start: DateTime(2026, 7, 10, 9, 0), available: false);
      final free =
          slot(id: 'free', start: DateTime(2026, 7, 10, 9, 0), available: true);
      final result = sanitizeBookableSlots([busy, free], now);
      expect(result.length, 1);
      expect(result.single.isAvailable, isTrue);
    });

    test('trie par date de début croissante', () {
      final later = slot(id: 'later', start: DateTime(2026, 7, 12, 9, 0));
      final sooner = slot(id: 'sooner', start: DateTime(2026, 7, 10, 9, 0));
      final result = sanitizeBookableSlots([later, sooner], now);
      expect(result.map((s) => s.id), ['sooner', 'later']);
    });
  });

  // --- BookableSlotsPage widget test ------------------------------------------
  group('BookableSlotsPage', () {
    late _MockBookableSlotsBloc bloc;

    setUp(() {
      bloc = _MockBookableSlotsBloc();
    });

    Widget buildPage() => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<BookableSlotsBloc>.value(
            value: bloc,
            child: const BookableSlotsPage(),
          ),
        );

    testWidgets('affiche le skeleton en état initial', (tester) async {
      when(() => bloc.state).thenReturn(const BookableSlotsInitial());
      await tester.pumpWidget(buildPage());
      expect(find.byType(NubiaSkeletonLoader), findsWidgets);
    });

    testWidgets('affiche le skeleton en état Loading', (tester) async {
      when(() => bloc.state).thenReturn(const BookableSlotsLoading());
      await tester.pumpWidget(buildPage());
      expect(find.byType(NubiaSkeletonLoader), findsWidgets);
    });

    testWidgets(
        'affiche les créneaux avec nom du praticien — aucun champ clinique',
        (tester) async {
      when(() => bloc.state).thenReturn(
        BookableSlotsLoaded([_slot], practitioners: _practitioners),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Disponible'), findsOneWidget);
      // #3467 : le nom du praticien est visible (en-tête de groupe + carte).
      expect(find.textContaining('Dr Alice Martin'), findsWidgets);
      // Cloisonnement : aucun libellé clinique ne doit apparaître
      expect(find.text('Motif'), findsNothing);
      expect(find.text('Notes médicales'), findsNothing);
      expect(find.textContaining('motif'), findsNothing);
      expect(find.textContaining('notes'), findsNothing);
    });

    testWidgets('affiche le filtre praticien quand le roster est présent',
        (tester) async {
      when(() => bloc.state).thenReturn(
        BookableSlotsLoaded([_slot], practitioners: _practitioners),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('slots_practitioner_filter')), findsOneWidget);
      expect(find.byKey(const Key('slots_date_filter')), findsOneWidget);
    });

    testWidgets('affiche un message si aucun créneau', (tester) async {
      when(() => bloc.state).thenReturn(const BookableSlotsLoaded([]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Aucun créneau'), findsOneWidget);
    });

    testWidgets('affiche l\'erreur en état BookableSlotsError', (tester) async {
      when(() => bloc.state)
          .thenReturn(const BookableSlotsError('Erreur réseau'));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Erreur réseau'), findsOneWidget);
    });

    testWidgets('affiche le snackbar sur SlotCreatedSuccess', (tester) async {
      whenListen(
        bloc,
        Stream.fromIterable([
          const BookableSlotsLoading(),
          const BookableSlotsSlotCreatedSuccess(),
        ]),
        initialState: const BookableSlotsInitial(),
      );
      await tester.pumpWidget(buildPage());
      await tester.pump();

      expect(find.text('Créneau ajouté'), findsOneWidget);
    });
  });

  // --- CreateSlotDialog --------------------------------------------------------
  group('CreateSlotDialog', () {
    Widget buildApp(
        {List<CabinetPractitioner> practitioners = _practitioners}) {
      return MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showDialog<CreateSlotResult>(
                context: ctx,
                builder: (_) => CreateSlotDialog(practitioners: practitioners),
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      );
    }

    testWidgets(
        's\'ouvre sans LateInitializationError et affiche les champs par défaut',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      expect(find.text('Créer un créneau'), findsOneWidget);
      expect(find.text('Praticien *'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Heure début'), findsOneWidget);
      expect(find.text('Heure fin'), findsOneWidget);
      expect(find.text('Créer'), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);
    });

    testWidgets('affiche la date du jour au format DD/MM/YYYY', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final day = now.day.toString().padLeft(2, '0');
      final month = now.month.toString().padLeft(2, '0');
      expect(find.textContaining('$day/$month/${now.year}'), findsOneWidget);
    });

    testWidgets('sans sélection de praticien, « Créer » affiche une erreur',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('confirm_create_slot_button')));
      await tester.pump();

      expect(find.text('Sélectionnez un praticien.'), findsOneWidget);
      // Le dialogue reste ouvert (pas de pop).
      expect(find.text('Créer un créneau'), findsOneWidget);
    });

    testWidgets('un praticien unique est présélectionné', (tester) async {
      await tester.pumpWidget(buildApp(practitioners: const [
        CabinetPractitioner(id: 'solo', displayName: 'Dr Seul'),
      ]));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      expect(find.text('Dr Seul'), findsOneWidget);
    });

    testWidgets('Annuler ferme le dialogue sans pop de valeur', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(find.text('Créer un créneau'), findsNothing);
    });
  });
}
