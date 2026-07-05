import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_secretariat/features/dashboard/dashboard_bloc.dart';
import 'package:app_secretariat/features/dashboard/dashboard_event.dart';
import 'package:app_secretariat/features/dashboard/dashboard_state.dart';

class _MockDashboardBloc extends MockBloc<DashboardEvent, DashboardState>
    implements DashboardBloc {}

Widget _wrap(DashboardBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<DashboardBloc>.value(
        value: bloc,
        child: Scaffold(
          body: BlocBuilder<DashboardBloc, DashboardState>(
            builder: (context, state) {
              if (state is DashboardLoaded) {
                return Column(
                  key: const Key('dashboard_loaded'),
                  children: [
                    Text('RDV: ${state.todayCount}',
                        key: const Key('stat_rdv_today')),
                    Text('En attente: ${state.pendingCount}',
                        key: const Key('stat_pending')),
                    Text('Liste attente: ${state.waitingCount}',
                        key: const Key('stat_waiting_list')),
                  ],
                );
              }
              if (state is DashboardError) {
                return Text(
                  state.message,
                  key: const Key('dashboard_error'),
                );
              }
              // DashboardInitial, DashboardLoading
              return const CircularProgressIndicator(
                key: Key('dashboard_loading'),
              );
            },
          ),
        ),
      ),
    );

class _MockGetAgenda extends Mock implements GetCabinetAgendaUseCase {}

class _MockListWaitingList extends Mock implements ListWaitingListUseCase {}

AgendaEntry _entry(String id, DateTime startsAt, {bool isFree = false}) =>
    AgendaEntry(
      id: id,
      cabinetId: 'cab',
      practitionerId: 'prac',
      practitionerName: 'Dr T',
      startsAt: startsAt,
      endsAt: startsAt.add(const Duration(minutes: 30)),
      isFree: isFree,
    );

void main() {
  group('DashboardBloc', () {
    late _MockGetAgenda getAgenda;
    late _MockListWaitingList listWaitingList;

    setUpAll(() {
      registerFallbackValue(DateTime(2026, 1, 1));
    });

    setUp(() {
      getAgenda = _MockGetAgenda();
      listWaitingList = _MockListWaitingList();
    });

    blocTest<DashboardBloc, DashboardState>(
      '#3362 : compteurs réels — RDV du jour, à confirmer, liste d\'attente',
      build: () {
        final now = DateTime.now();
        when(() => getAgenda(any(), includePast: any(named: 'includePast')))
            .thenAnswer((_) async => Right([
                  _entry('a1', now.add(const Duration(hours: 1))),
                  _entry('a2', now.add(const Duration(days: 1))),
                  _entry('libre', now, isFree: true),
                ]));
        when(() => listWaitingList()).thenAnswer(
          (_) async => Right([
            WaitingListEntry(
              id: 'w1',
              cabinetId: 'cab',
              patientId: 'p1',
              patientName: 'Marc Dubois',
              motif: '',
              requestedAt: DateTime(2026, 6, 21),
              position: 1,
            ),
          ]),
        );
        return DashboardBloc(
          getAgenda: getAgenda,
          listWaitingList: listWaitingList,
        );
      },
      act: (bloc) => bloc.add(const DashboardLoadRequested()),
      expect: () => [
        const DashboardLoading(),
        const DashboardLoaded(todayCount: 1, pendingCount: 2, waitingCount: 1),
      ],
    );

    blocTest<DashboardBloc, DashboardState>(
      'agenda en échec → DashboardError (pas un faux 0)',
      build: () {
        when(() => getAgenda(any(), includePast: any(named: 'includePast')))
            .thenAnswer((_) async => const Left(NetworkFailure()));
        when(() => listWaitingList()).thenAnswer((_) async => const Right([]));
        return DashboardBloc(
          getAgenda: getAgenda,
          listWaitingList: listWaitingList,
        );
      },
      act: (bloc) => bloc.add(const DashboardLoadRequested()),
      expect: () => [const DashboardLoading(), isA<DashboardError>()],
    );
  });

  group('Dashboard stats cards', () {
    late _MockDashboardBloc bloc;

    setUp(() {
      bloc = _MockDashboardBloc();
    });

    testWidgets('affiche le chargement en état DashboardInitial',
        (tester) async {
      when(() => bloc.state).thenReturn(const DashboardInitial());
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('dashboard_loading')), findsOneWidget);
    });

    testWidgets('affiche le chargement en état DashboardLoading',
        (tester) async {
      when(() => bloc.state).thenReturn(const DashboardLoading());
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('dashboard_loading')), findsOneWidget);
    });

    testWidgets('affiche une erreur en état DashboardError', (tester) async {
      when(() => bloc.state)
          .thenReturn(const DashboardError(message: 'Erreur test'));
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('dashboard_error')), findsOneWidget);
    });

    testWidgets('émet state avec counts → assert valeurs visibles',
        (tester) async {
      when(() => bloc.state).thenReturn(
        const DashboardLoaded(todayCount: 4, pendingCount: 2, waitingCount: 7),
      );
      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dashboard_loaded')), findsOneWidget);
      expect(find.text('RDV: 4'), findsOneWidget);
      expect(find.text('En attente: 2'), findsOneWidget);
      expect(find.text('Liste attente: 7'), findsOneWidget);
    });
  });
}
