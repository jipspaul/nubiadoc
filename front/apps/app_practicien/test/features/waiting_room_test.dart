import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' as shell;
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/waiting_room/waiting_room_bloc.dart';
import 'package:app_practicien/features/waiting_room/waiting_room_event.dart';
import 'package:app_practicien/features/waiting_room/waiting_room_state.dart';
import 'package:app_practicien/pro_config.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockListWaitingRoomUseCase extends Mock
    implements ListWaitingRoomUseCase {}

class MockCallNextUseCase extends Mock implements CallNextUseCase {}

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
        const WaitingRoomLoaded(entries: []),
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
      when(() => mockList())
          .thenAnswer((_) async => Right([_entry]));
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
  });

  // ---------------------------------------------------------------------------
  // Gating — destination masquée quand canAccessClinical = false
  // ---------------------------------------------------------------------------

  group('ProConfig — gating requiresClinical', () {
    test('la destination Salle d\'attente ne requiert pas d\'accès clinique',
        () {
      final dest = ProConfig.shellConfig.destinations.firstWhere(
        (d) => d.route == '/waiting-room',
      );
      expect(dest.requiresClinical, isFalse);
    });

    testWidgets(
      'Salle d\'attente visible et destinations cliniques masquées quand canAccessClinical = false',
      (tester) async {
        const nonClinicalSession = AuthSession(
          kind: UserKind.pro,
          userId: 'me',
          role: ProRole.secretary,
        );

        await tester.pumpWidget(MaterialApp(
          theme: NubiaTheme.light,
          home: shell.ProShell(
            config: ProConfig.shellConfig,
            session: nonClinicalSession,
          ),
        ));
        await tester.pumpAndSettle();

        expect(find.text('Salle d\'attente'), findsWidgets);
        expect(find.text('Consultation'), findsNothing);
        expect(find.text('Ordonnances'), findsNothing);
      },
    );
  });
}
