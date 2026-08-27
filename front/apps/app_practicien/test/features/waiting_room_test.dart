import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/waiting_room/waiting_room_bloc.dart';
import 'package:app_practicien/features/waiting_room/waiting_room_event.dart';
import 'package:app_practicien/features/waiting_room/waiting_room_page.dart';
import 'package:app_practicien/features/waiting_room/waiting_room_state.dart';
import 'package:app_practicien/pro_config.dart';
import 'package:app_practicien/session/pro_auth_cubit.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockListWaitingRoomUseCase extends Mock
    implements ListWaitingRoomUseCase {}

class MockCallNextUseCase extends Mock implements CallNextUseCase {}

class MockWaitingRoomBloc extends MockBloc<WaitingRoomEvent, WaitingRoomState>
    implements WaitingRoomBloc {}

class MockProAuthCubit extends MockCubit<AuthState> implements ProAuthCubit {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _entry = WaitingRoomEntry(
  id: 'wr-1',
  cabinetId: 'cab-1',
  patientId: 'pat-1',
  patientName: 'Marie Dupont',
  arrivedAt: DateTime.now().subtract(const Duration(minutes: 10)),
);

WaitingRoomBloc _makeBloc({
  required MockListWaitingRoomUseCase list,
  required MockCallNextUseCase callNext,
}) =>
    WaitingRoomBloc(listWaitingRoom: list, callNext: callNext);

Widget _wrap(WaitingRoomBloc bloc) => MaterialApp(
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(body: _WaitingRoomBodyDirect()),
      ),
    );

MockProAuthCubit _makeAuthCubit({required String userId}) {
  final cubit = MockProAuthCubit();
  when(() => cubit.state).thenReturn(
    AuthAuthenticated(
      AuthSession(
        kind: UserKind.pro,
        userId: userId,
        role: ProRole.practitioner,
      ),
    ),
  );
  return cubit;
}

/// Sur écran large (≥ [kPresencePanelBreakpoint]), la colonne latérale
/// dépend aussi de [ProAuthCubit] (#5039) — fournir les deux blocs.
Widget _wrapWide(WaitingRoomBloc bloc, ProAuthCubit authCubit) => MaterialApp(
      theme: NubiaTheme.light,
      home: MultiBlocProvider(
        providers: [
          BlocProvider<WaitingRoomBloc>.value(value: bloc),
          BlocProvider<ProAuthCubit>.value(value: authCubit),
        ],
        child: const Scaffold(body: WaitingRoomBody()),
      ),
    );

class _RefreshBodyDirect extends StatelessWidget {
  const _RefreshBodyDirect();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WaitingRoomBloc, WaitingRoomState>(
      builder: (context, state) {
        if (state is WaitingRoomLoaded && state.entries.isNotEmpty) {
          return RefreshIndicator(
            onRefresh: () {
              context
                  .read<WaitingRoomBloc>()
                  .add(const WaitingRoomLoadRequested());
              return Future<void>.delayed(Duration.zero);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                for (final e in state.entries)
                  Text(key: Key('entry_${e.id}'), e.patientName),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _WaitingRoomBodyDirect extends StatelessWidget {
  const _WaitingRoomBodyDirect();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WaitingRoomBloc, WaitingRoomState>(
      builder: (context, state) {
        if (state is WaitingRoomLoading || state is WaitingRoomInitial) {
          return const Center(
            key: Key('waiting_room_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is WaitingRoomError) {
          return Center(
            key: const Key('waiting_room_error'),
            child: Text(state.message),
          );
        }
        if (state is WaitingRoomLoaded) {
          if (state.entries.isEmpty) {
            return const Center(
              key: Key('waiting_room_empty'),
              child: Text('Salle d\'attente vide'),
            );
          }
          return ListView(
            children: [
              for (final e in state.entries)
                Text(key: Key('entry_${e.id}'), e.patientName),
              ElevatedButton(
                key: const Key('call_next_button'),
                onPressed: () => context
                    .read<WaitingRoomBloc>()
                    .add(const WaitingRoomCallNextRequested()),
                child: const Text('Patient suivant'),
              ),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Bloc tests
// ---------------------------------------------------------------------------

void main() {
  late MockListWaitingRoomUseCase mockList;
  late MockCallNextUseCase mockCallNext;

  setUpAll(() {
    registerFallbackValue(const WaitingRoomLoadRequested());
  });

  setUp(() {
    mockList = MockListWaitingRoomUseCase();
    mockCallNext = MockCallNextUseCase();
  });

  group('WaitingRoomBloc', () {
    blocTest<WaitingRoomBloc, WaitingRoomState>(
      'émet Loading puis Loaded avec les entrées',
      build: () {
        when(() => mockList()).thenAnswer((_) async => Right([_entry]));
        return _makeBloc(list: mockList, callNext: mockCallNext);
      },
      act: (bloc) => bloc.add(const WaitingRoomLoadRequested()),
      expect: () => [
        const WaitingRoomLoading(),
        WaitingRoomLoaded(entries: [_entry]),
      ],
    );

    blocTest<WaitingRoomBloc, WaitingRoomState>(
      'émet Loading puis Loaded vide quand salle vide',
      build: () {
        when(() => mockList()).thenAnswer((_) async => const Right([]));
        return _makeBloc(list: mockList, callNext: mockCallNext);
      },
      act: (bloc) => bloc.add(const WaitingRoomLoadRequested()),
      expect: () => [
        const WaitingRoomLoading(),
        WaitingRoomLoaded(entries: []),
      ],
    );

    blocTest<WaitingRoomBloc, WaitingRoomState>(
      'émet Error quand le chargement échoue',
      build: () {
        when(() => mockList()).thenAnswer(
          (_) async => Left(NetworkFailure('Réseau indisponible')),
        );
        return _makeBloc(list: mockList, callNext: mockCallNext);
      },
      act: (bloc) => bloc.add(const WaitingRoomLoadRequested()),
      expect: () => [
        const WaitingRoomLoading(),
        const WaitingRoomError('Réseau indisponible'),
      ],
    );

    blocTest<WaitingRoomBloc, WaitingRoomState>(
      'un rechargement en échec alors qu\'une liste est déjà affichée '
      'conserve la liste avec une reloadError (non bloquant)',
      build: () {
        when(() => mockList()).thenAnswer(
          (_) async => Left(NetworkFailure('Réseau indisponible')),
        );
        return _makeBloc(list: mockList, callNext: mockCallNext);
      },
      seed: () => WaitingRoomLoaded(entries: [_entry]),
      act: (bloc) => bloc.add(const WaitingRoomLoadRequested()),
      expect: () => [
        const WaitingRoomLoading(),
        WaitingRoomLoaded(
          entries: [_entry],
          reloadError: 'Réseau indisponible',
        ),
      ],
    );

    blocTest<WaitingRoomBloc, WaitingRoomState>(
      'un rechargement réussi efface une reloadError précédente',
      build: () {
        when(() => mockList()).thenAnswer((_) async => Right([_entry]));
        return _makeBloc(list: mockList, callNext: mockCallNext);
      },
      seed: () => WaitingRoomLoaded(
        entries: [_entry],
        reloadError: 'Réseau indisponible',
      ),
      act: (bloc) => bloc.add(const WaitingRoomLoadRequested()),
      expect: () => [
        const WaitingRoomLoading(),
        WaitingRoomLoaded(entries: [_entry]),
      ],
    );

    blocTest<WaitingRoomBloc, WaitingRoomState>(
      'CallNext recharge la liste après succès',
      build: () {
        when(() => mockList()).thenAnswer((_) async => Right([_entry]));
        when(() => mockCallNext()).thenAnswer((_) async => Right(_entry));
        return _makeBloc(list: mockList, callNext: mockCallNext);
      },
      seed: () => WaitingRoomLoaded(entries: [_entry]),
      act: (bloc) => bloc.add(const WaitingRoomCallNextRequested()),
      expect: () => [
        WaitingRoomLoaded(entries: [_entry], actionInProgress: true),
        const WaitingRoomLoading(),
        WaitingRoomLoaded(entries: [_entry]),
      ],
    );

    blocTest<WaitingRoomBloc, WaitingRoomState>(
      'CallNext conserve l\'état courant avec erreur en cas d\'échec',
      build: () {
        when(() => mockCallNext()).thenAnswer(
          (_) async => Left(NetworkFailure('Erreur réseau')),
        );
        return _makeBloc(list: mockList, callNext: mockCallNext);
      },
      seed: () => WaitingRoomLoaded(entries: [_entry]),
      act: (bloc) => bloc.add(const WaitingRoomCallNextRequested()),
      expect: () => [
        WaitingRoomLoaded(entries: [_entry], actionInProgress: true),
        WaitingRoomLoaded(
          entries: [_entry],
          actionInProgress: false,
          actionError: 'Erreur réseau',
        ),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // Widget tests
  // ---------------------------------------------------------------------------

  group('WaitingRoomPage (widget)', () {
    testWidgets('affiche le chargement initialement', (tester) async {
      when(() => mockList()).thenAnswer((_) async => Right([_entry]));
      final bloc = _makeBloc(list: mockList, callNext: mockCallNext);
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('waiting_room_loading')), findsOneWidget);
    });

    testWidgets('affiche la liste après chargement', (tester) async {
      when(() => mockList()).thenAnswer((_) async => Right([_entry]));
      final bloc = _makeBloc(list: mockList, callNext: mockCallNext)
        ..add(const WaitingRoomLoadRequested());
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('entry_wr-1')), findsOneWidget);
      expect(find.byKey(const Key('call_next_button')), findsOneWidget);
    });

    testWidgets('affiche l\'état vide quand aucun patient', (tester) async {
      when(() => mockList()).thenAnswer((_) async => const Right([]));
      final bloc = _makeBloc(list: mockList, callNext: mockCallNext)
        ..add(const WaitingRoomLoadRequested());
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('waiting_room_empty')), findsOneWidget);
    });

    testWidgets('affiche une erreur en cas d\'échec', (tester) async {
      when(() => mockList()).thenAnswer(
        (_) async => Left(NetworkFailure('Pas de réseau')),
      );
      final bloc = _makeBloc(list: mockList, callNext: mockCallNext)
        ..add(const WaitingRoomLoadRequested());
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('waiting_room_error')), findsOneWidget);
    });

    testWidgets(
        'affiche le panneau Praticiens présents et la note confidentialité '
        'sur large écran (#5040)', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      when(() => mockList()).thenAnswer((_) async => Right([_entry]));
      final bloc = _makeBloc(list: mockList, callNext: mockCallNext)
        ..add(const WaitingRoomLoadRequested());
      await tester.pumpWidget(
        _wrapWide(bloc, _makeAuthCubit(userId: 'prac-me')),
      );
      await tester.pump();

      expect(find.byKey(const Key('presence_panel')), findsOneWidget);
      expect(find.text('Praticiens présents'), findsOneWidget);
      expect(find.text('Dr Amélie Rousseau'), findsOneWidget);
      expect(find.text('Vous · en consultation'), findsOneWidget);
      expect(find.text('Présente'), findsOneWidget);
      expect(find.text('Dr Marc Lefèvre'), findsOneWidget);
      expect(find.text('Fauteuil 2 · termine à 18h'), findsOneWidget);
      expect(find.text('Départ 18h'), findsOneWidget);

      expect(
        find.byKey(const Key('waiting_room_confidentiality_note')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('waiting_room_confidentiality_note')),
          matching: find.byIcon(Icons.shield),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'La file affiche le motif administratif du rendez-vous. Les '
          'alertes cliniques ne figurent que sur la carte du prochain '
          'appelé.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'masque le panneau Praticiens présents sous le seuil de largeur '
        '(#5040)', (tester) async {
      when(() => mockList()).thenAnswer((_) async => Right([_entry]));
      final bloc = _makeBloc(list: mockList, callNext: mockCallNext)
        ..add(const WaitingRoomLoadRequested());
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<WaitingRoomBloc>.value(
            value: bloc,
            child: const Scaffold(body: WaitingRoomBody()),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('presence_panel')), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Carte hero « Prochain patient à appeler » (#5037)
  // ---------------------------------------------------------------------------

  group('Carte hero « Prochain patient à appeler » (#5037)', () {
    final heroEntry = WaitingRoomEntry(
      id: 'wr-1',
      cabinetId: 'cab-1',
      patientId: 'pat-1',
      patientName: 'Camille Moreau',
      arrivedAt: DateTime(2026, 1, 1, 14, 12),
      reason: 'Pose de couronne',
      appointmentTime: DateTime(2026, 1, 1, 14, 30),
    );
    final otherEntry = WaitingRoomEntry(
      id: 'wr-2',
      cabinetId: 'cab-1',
      patientId: 'pat-2',
      patientName: 'Théo Girard',
      arrivedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    );

    testWidgets(
        'affiche le 1er patient de la file : nom, motif, RDV et tag '
        'd\'arrivée', (tester) async {
      when(() => mockList())
          .thenAnswer((_) async => Right([heroEntry, otherEntry]));
      final bloc = _makeBloc(list: mockList, callNext: mockCallNext)
        ..add(const WaitingRoomLoadRequested());
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<WaitingRoomBloc>.value(
            value: bloc,
            child: const Scaffold(body: WaitingRoomBody()),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('next_patient_hero')), findsOneWidget);
      expect(find.text('PROCHAIN PATIENT À APPELER'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('next_patient_hero')),
          matching: find.text('Camille Moreau'),
        ),
        findsOneWidget,
      );
      expect(find.text('Pose de couronne · RDV de 14:30'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('next_patient_hero_arrival_tag')),
          matching: find.text('Arrivée à 14:12'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('next_patient_hero_call_button')),
        findsOneWidget,
      );
      expect(find.text('Appeler Camille Moreau'), findsOneWidget);
      expect(find.byIcon(Icons.campaign), findsOneWidget);
      expect(find.byKey(const Key('next_patient_hero_open_file')),
          findsOneWidget);
      expect(find.text('Ouvrir le dossier'), findsOneWidget);
      expect(find.byIcon(Icons.folder_open), findsOneWidget);
    });

    testWidgets('le bouton « Appeler » déclenche WaitingRoomCallNextRequested',
        (tester) async {
      when(() => mockList())
          .thenAnswer((_) async => Right([heroEntry, otherEntry]));
      when(() => mockCallNext())
          .thenAnswer((_) async => Right(heroEntry));
      final bloc = _makeBloc(list: mockList, callNext: mockCallNext)
        ..add(const WaitingRoomLoadRequested());
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<WaitingRoomBloc>.value(
            value: bloc,
            child: const Scaffold(body: WaitingRoomBody()),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('next_patient_hero_call_button')));
      await tester.pumpAndSettle();

      verify(() => mockCallNext()).called(1);
    });

    testWidgets('aucune carte hero quand la salle est vide', (tester) async {
      when(() => mockList()).thenAnswer((_) async => const Right([]));
      final bloc = _makeBloc(list: mockList, callNext: mockCallNext)
        ..add(const WaitingRoomLoadRequested());
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<WaitingRoomBloc>.value(
            value: bloc,
            child: const Scaffold(body: WaitingRoomBody()),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('next_patient_hero')), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Panneau « Mes patients dans la file » (#5039)
  // ---------------------------------------------------------------------------

  group('Mes patients dans la file (widget, #5039)', () {
    final entries = [
      WaitingRoomEntry(
        id: 'wr-1',
        cabinetId: 'cab-1',
        patientId: 'pat-1',
        patientName: 'Camille Moreau',
        arrivedAt: DateTime.now().subtract(const Duration(minutes: 32)),
        practitionerId: 'prac-me',
        practitionerName: 'Vous',
      ),
      WaitingRoomEntry(
        id: 'wr-2',
        cabinetId: 'cab-1',
        patientId: 'pat-2',
        patientName: 'Théo Girard',
        arrivedAt: DateTime.now().subtract(const Duration(minutes: 18)),
        practitionerId: 'prac-me',
        practitionerName: 'Vous',
      ),
      WaitingRoomEntry(
        id: 'wr-3',
        cabinetId: 'cab-1',
        patientId: 'pat-3',
        patientName: 'Léa Bernard',
        arrivedAt: DateTime.now().subtract(const Duration(minutes: 3)),
        practitionerId: 'prac-me',
        practitionerName: 'Vous',
      ),
      WaitingRoomEntry(
        id: 'wr-4',
        cabinetId: 'cab-1',
        patientId: 'pat-4',
        patientName: 'Sophie Roux',
        arrivedAt: DateTime.now().subtract(const Duration(minutes: 11)),
        practitionerId: 'prac-lefevre',
        practitionerName: 'Dr Lefèvre',
      ),
      WaitingRoomEntry(
        id: 'wr-5',
        cabinetId: 'cab-1',
        patientId: 'pat-5',
        patientName: 'Yanis Diallo',
        arrivedAt: DateTime.now().subtract(const Duration(minutes: 6)),
        reason: 'urgence',
      ),
    ];

    testWidgets('groupe la file par praticien avec les bons compteurs',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      when(() => mockList()).thenAnswer((_) async => Right(entries));
      final bloc = _makeBloc(list: mockList, callNext: mockCallNext)
        ..add(const WaitingRoomLoadRequested());
      await tester.pumpWidget(
        _wrapWide(bloc, _makeAuthCubit(userId: 'prac-me')),
      );
      await tester.pump();

      expect(find.byKey(const Key('my_patients_panel')), findsOneWidget);
      expect(find.text('Mes patients dans la file'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('my_patients_badge')),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('queue_breakdown_mine')),
          matching: find.text('Pour vous'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('queue_breakdown_mine')),
          matching: find.text('Camille, Théo, Léa'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('queue_breakdown_mine')),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('queue_breakdown_prac-lefevre')),
          matching: find.text('Pour Dr Lefèvre'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('queue_breakdown_prac-lefevre')),
          matching: find.text('Sophie Roux'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('queue_breakdown_prac-lefevre')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('queue_breakdown_unassigned')),
          matching: find.text('Non attribué'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('queue_breakdown_unassigned')),
          matching: find.text('Yanis Diallo · urgence'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('queue_breakdown_unassigned')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'la valeur « Pour vous » est en couleur brand, « Non attribué » en '
        'warning', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      when(() => mockList()).thenAnswer((_) async => Right(entries));
      final bloc = _makeBloc(list: mockList, callNext: mockCallNext)
        ..add(const WaitingRoomLoadRequested());
      await tester.pumpWidget(
        _wrapWide(bloc, _makeAuthCubit(userId: 'prac-me')),
      );
      await tester.pump();

      final tokens = NubiaTheme.light.extension<NubiaTokens>()!;

      final mineValue = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('queue_breakdown_mine')),
          matching: find.text('3'),
        ),
      );
      expect(mineValue.style?.color, NubiaColors.brand700);

      final unassignedValue = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('queue_breakdown_unassigned')),
          matching: find.text('1'),
        ),
      );
      expect(unassignedValue.style?.color, tokens.warningFg);
    });
  });

  // ---------------------------------------------------------------------------
  // Panneau « Rythme de la salle » (#5038)
  // ---------------------------------------------------------------------------

  group('Rythme de la salle (widget, #5038)', () {
    final entries = [
      WaitingRoomEntry(
        id: 'wr-1',
        cabinetId: 'cab-1',
        patientId: 'pat-1',
        patientName: 'Camille Moreau',
        arrivedAt: DateTime.now().subtract(const Duration(minutes: 32)),
      ),
      WaitingRoomEntry(
        id: 'wr-2',
        cabinetId: 'cab-1',
        patientId: 'pat-2',
        patientName: 'Théo Girard',
        arrivedAt: DateTime.now().subtract(const Duration(minutes: 18)),
      ),
      WaitingRoomEntry(
        id: 'wr-3',
        cabinetId: 'cab-1',
        patientId: 'pat-3',
        patientName: 'Léa Bernard',
        arrivedAt: DateTime.now().subtract(const Duration(minutes: 3)),
      ),
      WaitingRoomEntry(
        id: 'wr-4',
        cabinetId: 'cab-1',
        patientId: 'pat-4',
        patientName: 'Sophie Roux',
        arrivedAt: DateTime.now().subtract(const Duration(minutes: 11)),
      ),
      WaitingRoomEntry(
        id: 'wr-5',
        cabinetId: 'cab-1',
        patientId: 'pat-5',
        patientName: 'Yanis Diallo',
        arrivedAt: DateTime.now().subtract(const Duration(minutes: 6)),
      ),
    ];

    testWidgets(
        'affiche l\'attente moyenne et l\'attente la plus longue avec le nom '
        'du patient', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      when(() => mockList()).thenAnswer((_) async => Right(entries));
      final bloc = _makeBloc(list: mockList, callNext: mockCallNext)
        ..add(const WaitingRoomLoadRequested());
      await tester.pumpWidget(
        _wrapWide(bloc, _makeAuthCubit(userId: 'prac-me')),
      );
      await tester.pump();

      expect(find.byKey(const Key('room_pace_panel')), findsOneWidget);
      expect(find.text('Rythme de la salle'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('room_pace_average')),
          matching: find.text('Attente moyenne'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('room_pace_average')),
          matching: find.text('sur les 5 présents'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('room_pace_average')),
          matching: find.text('14 min'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('room_pace_longest')),
          matching: find.text('Attente la plus longue'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('room_pace_longest')),
          matching: find.text('Camille Moreau'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('room_pace_longest')),
          matching: find.text('32 min'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('la valeur de l\'attente la plus longue est en couleur '
        'warning', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      when(() => mockList()).thenAnswer((_) async => Right(entries));
      final bloc = _makeBloc(list: mockList, callNext: mockCallNext)
        ..add(const WaitingRoomLoadRequested());
      await tester.pumpWidget(
        _wrapWide(bloc, _makeAuthCubit(userId: 'prac-me')),
      );
      await tester.pump();

      final tokens = NubiaTheme.light.extension<NubiaTokens>()!;
      final longestValue = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('room_pace_longest')),
          matching: find.text('32 min'),
        ),
      );
      expect(longestValue.style?.color, tokens.warningFg);
    });
  });

  // ---------------------------------------------------------------------------
  // Rechargement en échec — erreur inline non bloquante
  // ---------------------------------------------------------------------------

  group('reloadError (widget)', () {
    testWidgets(
        'échec de rechargement conserve la liste et affiche NubiaInlineError',
        (tester) async {
      final mockBloc = MockWaitingRoomBloc();
      final loaded = WaitingRoomLoaded(entries: [_entry]);
      final withReloadError = WaitingRoomLoaded(
        entries: [_entry],
        reloadError: 'Réseau indisponible',
      );
      whenListen<WaitingRoomState>(
        mockBloc,
        Stream.fromIterable([withReloadError]),
        initialState: loaded,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<WaitingRoomBloc>.value(
            value: mockBloc,
            child: const Scaffold(body: WaitingRoomBody()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('waiting_room_error')), findsNothing);
      expect(find.byKey(const Key('entry_wr-1')), findsOneWidget);
      expect(
          find.byKey(const Key('waiting_room_reload_error')), findsOneWidget);
      expect(find.text('Réseau indisponible'), findsOneWidget);

      clearInteractions(mockBloc);
      await tester.tap(find.text('Réessayer'));
      verify(() => mockBloc.add(any(that: isA<WaitingRoomLoadRequested>())))
          .called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // Pull-to-refresh
  // ---------------------------------------------------------------------------

  group('pull-to-refresh', () {
    testWidgets('déclenche WaitingRoomLoadRequested au pull-to-refresh',
        (tester) async {
      final mockBloc = MockWaitingRoomBloc();
      final loadedState = WaitingRoomLoaded(entries: [_entry]);
      whenListen<WaitingRoomState>(
        mockBloc,
        Stream.fromIterable([loadedState]),
        initialState: loadedState,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<WaitingRoomBloc>.value(
            value: mockBloc,
            child: const Scaffold(body: _RefreshBodyDirect()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(ListView).first));
      await gesture.moveBy(const Offset(0, 300));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      verify(() => mockBloc.add(any(that: isA<WaitingRoomLoadRequested>())))
          .called(1);

      await tester.pumpAndSettle();
    });
  });

  // ---------------------------------------------------------------------------
  // Pull-to-refresh spinner — B3
  // ---------------------------------------------------------------------------

  group('pull-to-refresh spinner — B3', () {
    testWidgets('spinner reste visible jusqu\'à émission terminale',
        (tester) async {
      final mockBloc = MockWaitingRoomBloc();
      final loaded = WaitingRoomLoaded(entries: [_entry]);
      final ctrl = StreamController<WaitingRoomState>();

      whenListen<WaitingRoomState>(
        mockBloc,
        ctrl.stream,
        initialState: loaded,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<WaitingRoomBloc>.value(
            value: mockBloc,
            child: const Scaffold(body: WaitingRoomBody()),
          ),
        ),
      );
      await tester.pump(); // initState + BlocBuilder initial build

      // Trigger pull-to-refresh
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('waiting_room_refresh'))),
      );
      await gesture.moveBy(const Offset(0, 400));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      // Let snap animation play so spinner is fully visible
      await tester.pump(const Duration(milliseconds: 300));

      // Future still pending → spinner visible
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);

      // Emit terminal state → completer completes → dismiss animation
      ctrl.add(loaded);
      await tester.pump();
      // RefreshProgressIndicator has a repeating animation: pump explicit
      // duration rather than pumpAndSettle (which would never settle)
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(RefreshProgressIndicator), findsNothing);
      await ctrl.close();
    });
  });

  // ---------------------------------------------------------------------------
  // Indicateur de fraîcheur — barre de titre (#5035)
  // ---------------------------------------------------------------------------

  group('Indicateur de fraîcheur (widget, #5035)', () {
    testWidgets(
        'affiche « Mise à jour il y a … » dans la barre de titre après '
        'chargement', (tester) async {
      when(() => mockList()).thenAnswer((_) async => Right([_entry]));
      final bloc = _makeBloc(list: mockList, callNext: mockCallNext)
        ..add(const WaitingRoomLoadRequested());
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<WaitingRoomBloc>.value(
            value: bloc,
            child: const WaitingRoomPage(),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('waiting_room_freshness_indicator')),
        findsOneWidget,
      );
      expect(find.textContaining('Mise à jour il y a'), findsOneWidget);
    });

    testWidgets('pas d\'indicateur hors état Loaded (chargement)',
        (tester) async {
      final mockBloc = MockWaitingRoomBloc();
      when(() => mockBloc.state).thenReturn(const WaitingRoomLoading());
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<WaitingRoomBloc>.value(
            value: mockBloc,
            child: const WaitingRoomPage(),
          ),
        ),
      );

      expect(
        find.byKey(const Key('waiting_room_freshness_indicator')),
        findsNothing,
      );
    });
  });

  group('WaitingRoomLoaded.loadedAt (#5035)', () {
    blocTest<WaitingRoomBloc, WaitingRoomState>(
      'l\'horodatage de chargement se remet à jour à chaque rechargement '
      'réussi (manuel ou périodique)',
      build: () {
        when(() => mockList()).thenAnswer((_) async => Right([_entry]));
        return _makeBloc(list: mockList, callNext: mockCallNext);
      },
      act: (bloc) => bloc.add(const WaitingRoomLoadRequested()),
      verify: (bloc) {
        final loaded = bloc.state as WaitingRoomLoaded;
        expect(
          DateTime.now().difference(loaded.loadedAt).inSeconds,
          lessThan(5),
        );
      },
    );

    blocTest<WaitingRoomBloc, WaitingRoomState>(
      'un rechargement en échec conserve le loadedAt du chargement '
      'précédent (reloadError non bloquant)',
      build: () {
        when(() => mockList()).thenAnswer(
          (_) async => Left(NetworkFailure('Réseau indisponible')),
        );
        return _makeBloc(list: mockList, callNext: mockCallNext);
      },
      seed: () => WaitingRoomLoaded(
        entries: [_entry],
        loadedAt: DateTime(2020, 1, 1),
      ),
      act: (bloc) => bloc.add(const WaitingRoomLoadRequested()),
      verify: (bloc) {
        final loaded = bloc.state as WaitingRoomLoaded;
        expect(loaded.loadedAt, DateTime(2020, 1, 1));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Gating tests — destination cachée quand canAccessClinical = false
  // ---------------------------------------------------------------------------

  group('ProConfig — gating includeClinical', () {
    test('la destination Salle d\'attente requiert includeClinical', () {
      final dest = ProConfig.shellConfig.destinations.firstWhere(
        (d) => d.route == '/waiting-room',
      );
      expect(dest.requiresClinical, isTrue);
    });

    test('aucune destination sans requiresClinical n\'est sur /waiting-room',
        () {
      final nonClinical = ProConfig.shellConfig.destinations
          .where((d) => !d.requiresClinical)
          .map((d) => d.route);
      expect(nonClinical, isNot(contains('/waiting-room')));
    });
  });
}
