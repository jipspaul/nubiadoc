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
import 'package:app_secretariat/pro_config.dart';

class _MockSlotsRepository extends Mock implements SlotsRepository {}

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
    late ListBookableSlotsUseCase useCase;
    late CreateSlotUseCase createSlotUseCase;

    setUp(() {
      repo = _MockSlotsRepository();
      useCase = ListBookableSlotsUseCase(repo);
      createSlotUseCase = CreateSlotUseCase(repo);
    });

    blocTest<BookableSlotsBloc, BookableSlotsState>(
      'émet Loading puis Loaded sur succès',
      build: () {
        when(
          () => repo.list(
              from: any(named: 'from'),
              to: any(named: 'to'),
              practitionerId: any(named: 'practitionerId')),
        ).thenAnswer((_) async => Right([_slot]));
        return BookableSlotsBloc(
            listSlots: useCase, createSlot: createSlotUseCase);
      },
      act: (bloc) => bloc.add(const BookableSlotsLoadRequested()),
      expect: () => [
        const BookableSlotsLoading(),
        BookableSlotsLoaded([_slot]),
      ],
    );

    blocTest<BookableSlotsBloc, BookableSlotsState>(
      'émet Loading puis Error sur échec',
      build: () {
        when(
          () => repo.list(
              from: any(named: 'from'),
              to: any(named: 'to'),
              practitionerId: any(named: 'practitionerId')),
        ).thenAnswer(
          (_) async => Left(const NetworkFailure('Erreur réseau')),
        );
        return BookableSlotsBloc(
            listSlots: useCase, createSlot: createSlotUseCase);
      },
      act: (bloc) => bloc.add(const BookableSlotsLoadRequested()),
      expect: () => [
        const BookableSlotsLoading(),
        const BookableSlotsError('Erreur réseau'),
      ],
    );

    blocTest<BookableSlotsBloc, BookableSlotsState>(
      'create → émet Loading, SlotCreatedSuccess, Loading, Loaded',
      build: () {
        when(() => repo.create(any())).thenAnswer((_) async => Right(_slot));
        when(
          () => repo.list(
              from: any(named: 'from'),
              to: any(named: 'to'),
              practitionerId: any(named: 'practitionerId')),
        ).thenAnswer((_) async => Right([_slot]));
        return BookableSlotsBloc(
            listSlots: useCase, createSlot: createSlotUseCase);
      },
      act: (bloc) => bloc.add(CreateSlotRequested(
        startsAt: DateTime(2026, 6, 20, 9, 0),
        endsAt: DateTime(2026, 6, 20, 9, 30),
      )),
      expect: () => [
        const BookableSlotsLoading(),
        const BookableSlotsSlotCreatedSuccess(),
        const BookableSlotsLoading(),
        BookableSlotsLoaded([_slot]),
      ],
    );

    blocTest<BookableSlotsBloc, BookableSlotsState>(
      'les créneaux chargés n\'exposent aucun champ clinique',
      build: () {
        when(
          () => repo.list(
              from: any(named: 'from'),
              to: any(named: 'to'),
              practitionerId: any(named: 'practitionerId')),
        ).thenAnswer((_) async => Right([_slot]));
        return BookableSlotsBloc(
            listSlots: useCase, createSlot: createSlotUseCase);
      },
      act: (bloc) => bloc.add(const BookableSlotsLoadRequested()),
      verify: (bloc) {
        final loaded = bloc.state;
        expect(loaded, isA<BookableSlotsLoaded>());
        for (final slot in (loaded as BookableSlotsLoaded).slots) {
          expect(slot.startsAt, isNotNull);
          expect(slot.endsAt, isNotNull);
          // Slot n'a pas de motif ni notes cliniques —
          // contrainte garantie structurellement par le type.
        }
      },
    );
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

    testWidgets('affiche le chargement en état initial', (tester) async {
      when(() => bloc.state).thenReturn(const BookableSlotsInitial());
      await tester.pumpWidget(buildPage());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('affiche les créneaux — aucun champ clinique visible',
        (tester) async {
      when(() => bloc.state).thenReturn(BookableSlotsLoaded([_slot]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Disponible'), findsOneWidget);
      // Cloisonnement : aucun libellé clinique ne doit apparaître
      expect(find.text('Motif'), findsNothing);
      expect(find.text('Notes médicales'), findsNothing);
      expect(find.textContaining('motif'), findsNothing);
      expect(find.textContaining('notes'), findsNothing);
    });

    testWidgets('affiche un message si aucun créneau', (tester) async {
      when(() => bloc.state).thenReturn(const BookableSlotsLoaded([]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Aucun créneau disponible.'), findsOneWidget);
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
}
