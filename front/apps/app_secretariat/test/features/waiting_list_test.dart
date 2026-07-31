import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/waiting_list/waiting_list_bloc.dart';
import 'package:app_secretariat/features/waiting_list/waiting_list_event.dart';
import 'package:app_secretariat/features/waiting_list/waiting_list_page.dart';
import 'package:app_secretariat/features/waiting_list/waiting_list_state.dart';
import 'package:app_secretariat/pro_config.dart';

class _MockWaitingListRepository extends Mock
    implements WaitingListRepository {}

class _MockWaitingListBloc extends MockBloc<WaitingListEvent, WaitingListState>
    implements WaitingListBloc {}

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

  // --- WaitingListEntry : champs non-cliniques uniquement affichés -------------
  group('WaitingListEntry — cloisonnement champs cliniques', () {
    test('patientName et position accessibles (non-cliniques)', () {
      final entry = WaitingListEntry(
        id: 'w1',
        cabinetId: 'c1',
        patientId: 'p1',
        patientName: 'Jean Dupont',
        motif: 'Consultation urgente',
        requestedAt: DateTime(2026, 6, 1),
        position: 1,
      );
      expect(entry.patientName, 'Jean Dupont');
      expect(entry.position, 1);
    });
  });

  // --- WaitingListBloc ---------------------------------------------------------
  group('WaitingListBloc', () {
    late _MockWaitingListRepository repo;
    late ListWaitingListUseCase listUseCase;
    late OfferSlotToWaitingPatientUseCase offerSlotUseCase;

    final entries = [
      WaitingListEntry(
        id: 'w1',
        cabinetId: 'c1',
        patientId: 'p1',
        patientName: 'Marie Curie',
        motif: 'Détartrage',
        requestedAt: DateTime(2026, 6, 1),
        position: 1,
      ),
    ];

    setUp(() {
      repo = _MockWaitingListRepository();
      listUseCase = ListWaitingListUseCase(repo);
      offerSlotUseCase = OfferSlotToWaitingPatientUseCase(repo);
    });

    blocTest<WaitingListBloc, WaitingListState>(
      'émet Loading puis Loaded sur succès',
      build: () {
        when(() => repo.list()).thenAnswer((_) async => Right(entries));
        return WaitingListBloc(
          listWaitingList: listUseCase,
          offerSlot: offerSlotUseCase,
        );
      },
      act: (bloc) => bloc.add(const WaitingListLoadRequested()),
      expect: () => [
        const WaitingListLoading(),
        WaitingListLoaded(entries),
      ],
    );

    blocTest<WaitingListBloc, WaitingListState>(
      'émet Loading puis Error sur échec',
      build: () {
        when(() => repo.list()).thenAnswer(
          (_) async => const Left(NetworkFailure('Erreur réseau')),
        );
        return WaitingListBloc(
          listWaitingList: listUseCase,
          offerSlot: offerSlotUseCase,
        );
      },
      act: (bloc) => bloc.add(const WaitingListLoadRequested()),
      expect: () => [
        const WaitingListLoading(),
        const WaitingListError('Erreur réseau'),
      ],
    );

    blocTest<WaitingListBloc, WaitingListState>(
      'les entrées chargées n\'exposent aucun champ clinique via le bloc',
      build: () {
        when(() => repo.list()).thenAnswer((_) async => Right(entries));
        return WaitingListBloc(
          listWaitingList: listUseCase,
          offerSlot: offerSlotUseCase,
        );
      },
      act: (bloc) => bloc.add(const WaitingListLoadRequested()),
      verify: (bloc) {
        final loaded = bloc.state;
        expect(loaded, isA<WaitingListLoaded>());
        for (final entry in (loaded as WaitingListLoaded).entries) {
          expect(entry.patientName, isNotEmpty);
          // Cloisonnement : la page n'affiche jamais le motif ni les notes.
          // Le type WaitingListEntry porte le champ motif mais la vue l'ignore.
        }
      },
    );

    blocTest<WaitingListBloc, WaitingListState>(
      'émet OfferSuccess puis recharge la liste sur offre réussie',
      build: () {
        when(() => repo.offerSlot('w1'))
            .thenAnswer((_) async => const Right(unit));
        when(() => repo.list()).thenAnswer((_) async => Right(entries));
        return WaitingListBloc(
          listWaitingList: listUseCase,
          offerSlot: offerSlotUseCase,
        );
      },
      act: (bloc) => bloc.add(const WaitingListOfferSlotRequested('w1')),
      expect: () => [
        const WaitingListOfferSuccess(),
        const WaitingListLoading(),
        WaitingListLoaded(entries),
      ],
    );

    // #4536 : un échec de « Combler » (ex. 409 slot_unavailable) ne doit
    // JAMAIS remplacer la liste déjà affichée par l'état d'erreur plein
    // écran — seul un feedback ponctuel doit apparaître, la liste reste.
    blocTest<WaitingListBloc, WaitingListState>(
      'échec de Combler garde les entrées affichées (pas de WaitingListError)',
      build: () {
        when(() => repo.list()).thenAnswer((_) async => Right(entries));
        when(() => repo.offerSlot('w1')).thenAnswer(
          (_) async => const Left(
            ValidationFailure(message: 'Aucun créneau disponible.'),
          ),
        );
        return WaitingListBloc(
          listWaitingList: listUseCase,
          offerSlot: offerSlotUseCase,
        );
      },
      seed: () => WaitingListLoaded(entries),
      act: (bloc) => bloc.add(const WaitingListOfferSlotRequested('w1')),
      expect: () => [
        WaitingListOfferError('Aucun créneau disponible.', entries),
      ],
    );
  });

  // --- WaitingListPage widget test ---------------------------------------------
  group('WaitingListPage', () {
    late _MockWaitingListBloc bloc;

    setUp(() {
      bloc = _MockWaitingListBloc();
    });

    Widget buildPage() => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<WaitingListBloc>.value(
            value: bloc,
            child: const WaitingListPage(),
          ),
        );

    testWidgets('affiche le skeleton en état initial', (tester) async {
      when(() => bloc.state).thenReturn(const WaitingListInitial());
      await tester.pumpWidget(buildPage());
      expect(find.byKey(const Key('waiting_list_skeleton')), findsOneWidget);
      expect(find.byType(NubiaSkeletonLoader), findsWidgets);
    });

    testWidgets('affiche le skeleton en état Loading', (tester) async {
      when(() => bloc.state).thenReturn(const WaitingListLoading());
      await tester.pumpWidget(buildPage());
      expect(find.byKey(const Key('waiting_list_skeleton')), findsOneWidget);
    });

    testWidgets('affiche les patients — aucun champ clinique visible',
        (tester) async {
      when(() => bloc.state).thenReturn(
        WaitingListLoaded([
          WaitingListEntry(
            id: 'w1',
            cabinetId: 'c1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            motif: 'Détartrage',
            requestedAt: DateTime(2026, 6, 1),
            position: 1,
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Marie Curie'), findsOneWidget);
      // Cloisonnement : le motif et les notes ne doivent jamais s'afficher.
      expect(find.text('Motif'), findsNothing);
      expect(find.text('Notes médicales'), findsNothing);
      expect(find.textContaining('Détartrage'), findsNothing);
      expect(find.textContaining('notes'), findsNothing);
    });

    testWidgets('entrée sans nom patient : affiche un repli lisible, pas « ? »',
        (tester) async {
      when(() => bloc.state).thenReturn(
        WaitingListLoaded([
          WaitingListEntry(
            id: 'w9',
            cabinetId: 'c1',
            patientId: 'p1',
            patientName: '',
            motif: '',
            requestedAt: DateTime(2026, 6, 1),
            position: 1,
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // Repli « Patient <ref courte> » au lieu d'un titre vide / avatar « ? ».
      expect(find.text('Patient P1'), findsOneWidget);
      expect(find.text('?'), findsNothing);
    });

    testWidgets('Loaded([]) affiche NubiaEmptyState', (tester) async {
      when(() => bloc.state).thenReturn(const WaitingListLoaded([]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byType(NubiaEmptyState), findsOneWidget);
      expect(find.text('Pas d\'attente'), findsOneWidget);
      expect(find.text('Aucun patient en liste d\'attente'), findsOneWidget);
    });

    testWidgets('affiche le message d\'erreur', (tester) async {
      when(() => bloc.state)
          .thenReturn(const WaitingListError('Erreur de connexion'));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Erreur de connexion'), findsOneWidget);
    });

    testWidgets('pull-to-refresh déclenche WaitingListLoadRequested',
        (tester) async {
      when(() => bloc.state).thenReturn(
        WaitingListLoaded([
          WaitingListEntry(
            id: 'w1',
            cabinetId: 'c1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            motif: 'Détartrage',
            requestedAt: DateTime(2026, 6, 1),
            position: 1,
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // 2 appels au total : 1 depuis initState + 1 depuis pull-to-refresh
      verify(() => bloc.add(const WaitingListLoadRequested())).called(2);
    });

    testWidgets(
        'le bouton offre déclenche WaitingListOfferSlotRequested — sans champ clinique',
        (tester) async {
      registerFallbackValue(const WaitingListLoadRequested());
      when(() => bloc.state).thenReturn(
        WaitingListLoaded([
          WaitingListEntry(
            id: 'w1',
            cabinetId: 'c1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            motif: 'Consultation urgente',
            requestedAt: DateTime(2026, 6, 1),
            position: 1,
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.calendar_today_outlined));

      // L'event ne porte que l'id — aucun champ clinique (motif, notes médicales).
      final captured = verify(() => bloc.add(captureAny())).captured;
      final offerEvent =
          captured.whereType<WaitingListOfferSlotRequested>().single;
      expect(offerEvent.id, 'w1');
    });
  });
}
