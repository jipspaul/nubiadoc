import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/waiting_room/waiting_room_bloc.dart';
import 'package:app_secretariat/features/waiting_room/waiting_room_event.dart';
import 'package:app_secretariat/features/waiting_room/waiting_room_page.dart';
import 'package:app_secretariat/features/waiting_room/waiting_room_state.dart';
import 'package:app_secretariat/pro_config.dart';

class _MockWaitingRoomRepository extends Mock
    implements WaitingRoomRepository {}

class _MockWaitingRoomBloc extends MockBloc<WaitingRoomEvent, WaitingRoomState>
    implements WaitingRoomBloc {}

void main() {
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

  // --- WaitingRoomEntry : pas de champ clinique --------------------------------
  group('WaitingRoomEntry — cloisonnement champs cliniques', () {
    test('patientName accessible (non-clinique)', () {
      final entry = WaitingRoomEntry(
        id: 'e1',
        cabinetId: 'c1',
        patientId: 'p1',
        patientName: 'Jean Dupont',
        arrivedAt: DateTime(2026, 6, 19, 9, 0),
      );
      expect(entry.patientName, 'Jean Dupont');
    });
  });

  // --- WaitingRoomBloc ---------------------------------------------------------
  group('WaitingRoomBloc', () {
    late _MockWaitingRoomRepository repo;
    late ListWaitingRoomUseCase listUseCase;
    late CallNextUseCase callNextUseCase;

    final entries = [
      WaitingRoomEntry(
        id: 'e1',
        cabinetId: 'c1',
        patientId: 'p1',
        patientName: 'Marie Curie',
        arrivedAt: DateTime(2026, 6, 19, 9, 0),
      ),
    ];

    setUp(() {
      repo = _MockWaitingRoomRepository();
      listUseCase = ListWaitingRoomUseCase(repo);
      callNextUseCase = CallNextUseCase(repo);
    });

    blocTest<WaitingRoomBloc, WaitingRoomState>(
      'émet Loading puis Loaded sur succès',
      build: () {
        when(() => repo.list()).thenAnswer((_) async => Right(entries));
        return WaitingRoomBloc(
          listWaitingRoom: listUseCase,
          callNext: callNextUseCase,
        );
      },
      act: (bloc) => bloc.add(const WaitingRoomLoadRequested()),
      expect: () => [
        const WaitingRoomLoading(),
        WaitingRoomLoaded(entries),
      ],
    );

    blocTest<WaitingRoomBloc, WaitingRoomState>(
      'émet Loading puis Error sur échec',
      build: () {
        when(() => repo.list()).thenAnswer(
          (_) async => Left(
            const NetworkFailure('Erreur réseau'),
          ),
        );
        return WaitingRoomBloc(
          listWaitingRoom: listUseCase,
          callNext: callNextUseCase,
        );
      },
      act: (bloc) => bloc.add(const WaitingRoomLoadRequested()),
      expect: () => [
        const WaitingRoomLoading(),
        const WaitingRoomError('Erreur réseau'),
      ],
    );

    blocTest<WaitingRoomBloc, WaitingRoomState>(
      'les entrées chargées n\'exposent aucun champ clinique',
      build: () {
        when(() => repo.list()).thenAnswer((_) async => Right(entries));
        return WaitingRoomBloc(
          listWaitingRoom: listUseCase,
          callNext: callNextUseCase,
        );
      },
      act: (bloc) => bloc.add(const WaitingRoomLoadRequested()),
      verify: (bloc) {
        final loaded = bloc.state;
        expect(loaded, isA<WaitingRoomLoaded>());
        for (final entry in (loaded as WaitingRoomLoaded).entries) {
          expect(entry.patientName, isNotEmpty);
          // WaitingRoomEntry porte `reason` (motif admin, ex. "Détartrage" —
          // #5172) mais aucun champ clinique (notes médicales, diagnostic) :
          // cette dernière contrainte est garantie structurellement par le type.
        }
      },
    );
  });

  // --- WaitingRoomPage widget test ---------------------------------------------
  group('WaitingRoomPage', () {
    late _MockWaitingRoomBloc bloc;

    setUp(() {
      bloc = _MockWaitingRoomBloc();
    });

    Widget buildPage() => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<WaitingRoomBloc>.value(
            value: bloc,
            child: const WaitingRoomPage(),
          ),
        );

    testWidgets('affiche le chargement en état initial', (tester) async {
      when(() => bloc.state).thenReturn(const WaitingRoomInitial());
      await tester.pumpWidget(buildPage());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('affiche les patients — aucun champ clinique visible',
        (tester) async {
      when(() => bloc.state).thenReturn(
        WaitingRoomLoaded([
          WaitingRoomEntry(
            id: 'e1',
            cabinetId: 'c1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            arrivedAt: DateTime(2026, 6, 19, 9, 0),
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Marie Curie'), findsOneWidget);
      // Cloisonnement : aucun libellé clinique ne doit apparaître
      expect(find.text('Motif'), findsNothing);
      expect(find.text('Notes médicales'), findsNothing);
      expect(find.textContaining('motif'), findsNothing);
      expect(find.textContaining('notes'), findsNothing);
    });

    testWidgets(
        'sous-titre = motif + heure de RDV, plus de Position/Arrivé — #5172',
        (tester) async {
      when(() => bloc.state).thenReturn(
        WaitingRoomLoaded([
          WaitingRoomEntry(
            id: 'e1',
            cabinetId: 'c1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            arrivedAt: DateTime(2026, 6, 19, 9, 0),
            reason: 'Détartrage',
            appointmentTime: DateTime(2026, 6, 19, 10, 0),
          ),
          WaitingRoomEntry(
            id: 'e2',
            cabinetId: 'c1',
            patientId: 'p2',
            patientName: 'Paul Martin',
            arrivedAt: DateTime(2026, 6, 19, 9, 30),
            reason: 'Douleur dentaire',
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Détartrage · RDV 10:00'), findsOneWidget);
      expect(find.text('Douleur dentaire'), findsOneWidget);
      expect(find.textContaining('Position'), findsNothing);
      expect(find.textContaining('Arrivé il y a'), findsNothing);
    });

    testWidgets(
        'urgence sans RDV — pastille Sans RDV, praticien Non attribué, '
        'action Attribuer — #5171', (tester) async {
      when(() => bloc.state).thenReturn(
        WaitingRoomLoaded([
          WaitingRoomEntry(
            id: 'e1',
            cabinetId: 'c1',
            patientId: 'p1',
            patientName: 'Léa Bernard',
            arrivedAt: DateTime(2026, 6, 19, 9, 0),
            reason: 'Douleur dentaire',
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Sans RDV'), findsOneWidget);
      expect(find.text('Non attribué'), findsOneWidget);
      expect(find.text('Attribuer'), findsOneWidget);
      expect(find.text('En attente'), findsNothing);
    });

    testWidgets(
        'RDV normal — pastille En attente, pas de Sans RDV/Attribuer — #5171',
        (tester) async {
      when(() => bloc.state).thenReturn(
        WaitingRoomLoaded([
          WaitingRoomEntry(
            id: 'e1',
            cabinetId: 'c1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            appointmentId: 'appt-1',
            arrivedAt: DateTime(2026, 6, 19, 9, 0),
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('En attente'), findsOneWidget);
      expect(find.text('Sans RDV'), findsNothing);
      expect(find.text('Non attribué'), findsNothing);
      expect(find.text('Attribuer'), findsNothing);
    });

    testWidgets('affiche un message si la salle est vide', (tester) async {
      when(() => bloc.state).thenReturn(const WaitingRoomLoaded([]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(
        find.text('Aucun patient en salle d\'attente.'),
        findsOneWidget,
      );
    });

    testWidgets('FAB désactivé quand liste vide', (tester) async {
      when(() => bloc.state).thenReturn(const WaitingRoomLoaded([]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.onPressed, isNull);
    });

    testWidgets('FAB actif quand patients présents', (tester) async {
      when(() => bloc.state).thenReturn(
        WaitingRoomLoaded([
          WaitingRoomEntry(
            id: 'e2',
            cabinetId: 'c1',
            patientId: 'p2',
            patientName: 'Paul Martin',
            arrivedAt: DateTime(2026, 6, 20, 8, 0),
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.onPressed, isNotNull);
    });

    testWidgets(
        'affiche le récap KPI (en attente / moyenne / au-delà de 30 min) — #5173',
        (tester) async {
      final now = DateTime.now();
      when(() => bloc.state).thenReturn(
        WaitingRoomLoaded([
          WaitingRoomEntry(
            id: 'e1',
            cabinetId: 'c1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            arrivedAt: now.subtract(const Duration(minutes: 10)),
          ),
          WaitingRoomEntry(
            id: 'e2',
            cabinetId: 'c1',
            patientId: 'p2',
            patientName: 'Paul Martin',
            arrivedAt: now.subtract(const Duration(minutes: 40)),
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('waiting_room_kpi_count')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('waiting_room_kpi_average')),
          matching: find.text('25 min'),
        ),
        findsOneWidget,
      );

      final overThirtyValue = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('waiting_room_kpi_over_thirty')),
          matching: find.text('1'),
        ),
      );
      expect(overThirtyValue.style?.color, NubiaTokens.light.dangerFg);
    });

    testWidgets('file vide → KPI à 0 / 0 min / 0, pas de division par zéro',
        (tester) async {
      when(() => bloc.state).thenReturn(const WaitingRoomLoaded([]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('waiting_room_kpi_count')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('waiting_room_kpi_average')),
          matching: find.text('0 min'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('waiting_room_kpi_over_thirty')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('pas de bandeau KPI hors état Loaded (chargement)',
        (tester) async {
      when(() => bloc.state).thenReturn(const WaitingRoomInitial());
      await tester.pumpWidget(buildPage());

      expect(find.byKey(const Key('waiting_room_kpi_count')), findsNothing);
    });
  });
}
