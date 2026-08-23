import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
            practitionerId: 'pr-1',
            practitionerName: 'Dr A. Rousseau',
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

    testWidgets(
        'colonne Estimation — valeur non nulle affichée en "~N min" — #5169',
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
            estimatedWaitMinutes: 12,
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('waiting_entry_estimation_e1')),
          matching: find.text('~12 min'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'colonne Estimation — nulle en tête de file → "—" + "à appeler", '
        'jamais de valeur inventée — #5169', (tester) async {
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

      final estimation = find.byKey(const Key('waiting_entry_estimation_e1'));
      expect(
        find.descendant(of: estimation, matching: find.text('—')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: estimation, matching: find.text('à appeler')),
        findsOneWidget,
      );
    });

    testWidgets(
        'colonne Estimation — nulle, sans RDV et pas en tête de file → '
        '"—" + "à évaluer" — #5169', (tester) async {
      when(() => bloc.state).thenReturn(
        WaitingRoomLoaded([
          WaitingRoomEntry(
            id: 'e1',
            cabinetId: 'c1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            appointmentId: 'appt-1',
            arrivedAt: DateTime(2026, 6, 19, 9, 0),
            estimatedWaitMinutes: 5,
          ),
          WaitingRoomEntry(
            id: 'e2',
            cabinetId: 'c1',
            patientId: 'p2',
            patientName: 'Léa Bernard',
            arrivedAt: DateTime(2026, 6, 19, 9, 5),
            reason: 'Douleur dentaire',
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      final estimation = find.byKey(const Key('waiting_entry_estimation_e2'));
      expect(
        find.descendant(of: estimation, matching: find.text('—')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: estimation, matching: find.text('à évaluer')),
        findsOneWidget,
      );
    });

    testWidgets(
        'colonne Praticien — nom + pastille couleur du practitionerId — #5168',
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
            practitionerId: 'pr-rousseau',
            practitionerName: 'Dr A. Rousseau',
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      final column = find.byKey(const Key('waiting_entry_practitioner_e1'));
      expect(
        find.descendant(of: column, matching: find.text('Dr A. Rousseau')),
        findsOneWidget,
      );
      final dot = tester.widget<Container>(
        find.descendant(of: column, matching: find.byType(Container)),
      );
      final decoration = dot.decoration as BoxDecoration;
      expect(decoration.color, practitionerColor('pr-rousseau'));
    });

    testWidgets(
        'colonne Praticien — "Non attribué" et pastille neutre sans '
        'practitionerId — #5168', (tester) async {
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

      final column = find.byKey(const Key('waiting_entry_practitioner_e1'));
      expect(
        find.descendant(of: column, matching: find.text('Non attribué')),
        findsOneWidget,
      );
      final dot = tester.widget<Container>(
        find.descendant(of: column, matching: find.byType(Container)),
      );
      final decoration = dot.decoration as BoxDecoration;
      expect(decoration.color, practitionerUnassignedColor);
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

    testWidgets('pas de FloatingActionButton — action call-next en barre '
        "d'outils — #5167", (tester) async {
      when(() => bloc.state).thenReturn(const WaitingRoomLoaded([]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(
        find.byKey(const Key('waiting_room_call_next_button')),
        findsOneWidget,
      );
    });

    testWidgets('action call-next désactivée quand liste vide — #5167',
        (tester) async {
      when(() => bloc.state).thenReturn(const WaitingRoomLoaded([]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      final button = tester.widget<NubiaButton>(
        find.byKey(const Key('waiting_room_call_next_button')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('action call-next active quand patients présents — #5167',
        (tester) async {
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

      final button = tester.widget<NubiaButton>(
        find.byKey(const Key('waiting_room_call_next_button')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets(
        '⌘⏎ déclenche WaitingRoomCallNextRequested quand la file '
        "n'est pas vide — #5167", (tester) async {
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

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();

      verify(() => bloc.add(const WaitingRoomCallNextRequested())).called(1);
    });

    testWidgets('⌘⏎ ne fait rien quand la file est vide — #5167',
        (tester) async {
      when(() => bloc.state).thenReturn(const WaitingRoomLoaded([]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();

      verifyNever(() => bloc.add(const WaitingRoomCallNextRequested()));
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

    testWidgets(
        'aucune entrée > 30 min → pas de bandeau d\'alerte — #5170',
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
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('waiting_room_alert_banner')),
        findsNothing,
      );
      // La liste reste visible.
      expect(find.byKey(const Key('waiting_room_list')), findsOneWidget);
    });

    testWidgets(
        'entrée > 30 min → bandeau nommant le patient le plus en retard, '
        'action Prévenir le praticien, liste toujours visible — #5170',
        (tester) async {
      final now = DateTime.now();
      when(() => bloc.state).thenReturn(
        WaitingRoomLoaded([
          WaitingRoomEntry(
            id: 'e1',
            cabinetId: 'c1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            arrivedAt: now.subtract(const Duration(minutes: 38)),
          ),
          WaitingRoomEntry(
            id: 'e2',
            cabinetId: 'c1',
            patientId: 'p2',
            patientName: 'Paul Martin',
            arrivedAt: now.subtract(const Duration(minutes: 10)),
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('waiting_room_alert_banner')),
        findsOneWidget,
      );
      expect(find.textContaining('Marie Curie attend depuis 38 min'),
          findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('waiting_room_alert_banner')),
          matching: find.text('Prévenir le praticien'),
        ),
        findsOneWidget,
      );
      // Le bandeau s'ajoute au-dessus de la liste, sans la masquer.
      expect(find.byKey(const Key('waiting_room_list')), findsOneWidget);
      expect(find.text('Marie Curie'), findsOneWidget);
      expect(find.text('Paul Martin'), findsOneWidget);
    });

    testWidgets(
        'chaque ligne (hors sans-RDV) a son propre bouton Appeler, tête de '
        'file en variant plein — #5166', (tester) async {
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
          WaitingRoomEntry(
            id: 'e2',
            cabinetId: 'c1',
            patientId: 'p2',
            patientName: 'Paul Martin',
            appointmentId: 'appt-2',
            arrivedAt: DateTime(2026, 6, 19, 9, 5),
          ),
          // Sans-RDV : pas de bouton Appeler (déjà l'action Attribuer).
          WaitingRoomEntry(
            id: 'e3',
            cabinetId: 'c1',
            patientId: 'p3',
            patientName: 'Léa Bernard',
            arrivedAt: DateTime(2026, 6, 19, 9, 10),
            reason: 'Douleur dentaire',
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('waiting_entry_call_button_e1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('waiting_entry_call_button_e2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('waiting_entry_call_button_e3')),
        findsNothing,
      );

      final headButton = tester.widget<NubiaButton>(
        find.byKey(const Key('waiting_entry_call_button_e1')),
      );
      expect(headButton.variant, NubiaButtonVariant.primary);

      final otherButton = tester.widget<NubiaButton>(
        find.byKey(const Key('waiting_entry_call_button_e2')),
      );
      expect(otherButton.variant, NubiaButtonVariant.secondary);
    });

    testWidgets(
        'tap sur le bouton Appeler d\'une ligne dispatche '
        'WaitingRoomCallRequested pour CETTE entrée — #5166', (tester) async {
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
          WaitingRoomEntry(
            id: 'e2',
            cabinetId: 'c1',
            patientId: 'p2',
            patientName: 'Paul Martin',
            appointmentId: 'appt-2',
            arrivedAt: DateTime(2026, 6, 19, 9, 5),
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('waiting_entry_call_button_e2')));
      await tester.pumpAndSettle();

      verify(() => bloc.add(const WaitingRoomCallRequested('e2'))).called(1);
      verifyNever(() => bloc.add(const WaitingRoomCallRequested('e1')));
    });
  });

  // --- WaitingRoomBloc — appel par ligne (#5166) -------------------------------
  group('WaitingRoomBloc — WaitingRoomCallRequested (#5166)', () {
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
      WaitingRoomEntry(
        id: 'e2',
        cabinetId: 'c1',
        patientId: 'p2',
        patientName: 'Paul Martin',
        arrivedAt: DateTime(2026, 6, 19, 9, 5),
      ),
      WaitingRoomEntry(
        id: 'e3',
        cabinetId: 'c1',
        patientId: 'p3',
        patientName: 'Léa Bernard',
        arrivedAt: DateTime(2026, 6, 19, 9, 10),
      ),
    ];

    setUp(() {
      repo = _MockWaitingRoomRepository();
      listUseCase = ListWaitingRoomUseCase(repo);
      callNextUseCase = CallNextUseCase(repo);
    });

    blocTest<WaitingRoomBloc, WaitingRoomState>(
      'appeler la tête de file appelle bien le back (callNext)',
      build: () {
        when(() => repo.callNext()).thenAnswer((_) async => Right(entries[0]));
        when(() => repo.list()).thenAnswer((_) async => Right(entries));
        return WaitingRoomBloc(
          listWaitingRoom: listUseCase,
          callNext: callNextUseCase,
        );
      },
      seed: () => WaitingRoomLoaded(entries),
      act: (bloc) => bloc.add(const WaitingRoomCallRequested('e1')),
      verify: (_) {
        verify(() => repo.callNext()).called(1);
      },
    );

    blocTest<WaitingRoomBloc, WaitingRoomState>(
      'appeler la ligne 3 (e3) ne déclenche aucun appel back — n\'appelle '
      'pas la ligne 1',
      build: () {
        when(() => repo.callNext()).thenAnswer((_) async => Right(entries[0]));
        return WaitingRoomBloc(
          listWaitingRoom: listUseCase,
          callNext: callNextUseCase,
        );
      },
      seed: () => WaitingRoomLoaded(entries),
      act: (bloc) => bloc.add(const WaitingRoomCallRequested('e3')),
      expect: () => <WaitingRoomState>[],
      verify: (_) {
        verifyNever(() => repo.callNext());
      },
    );
  });
}
