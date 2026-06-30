import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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

void main() {
  group('DashboardBloc', () {
    blocTest<DashboardBloc, DashboardState>(
      'émet Loading puis Loaded avec les counts à 0',
      build: DashboardBloc.new,
      act: (bloc) => bloc.add(const DashboardLoadRequested()),
      expect: () => [
        const DashboardLoading(),
        const DashboardLoaded(todayCount: 0, pendingCount: 0, waitingCount: 0),
      ],
    );
  });

  group('Dashboard stats cards', () {
    late _MockDashboardBloc bloc;

    setUp(() {
      bloc = _MockDashboardBloc();
    });

    testWidgets('affiche le chargement en état DashboardInitial', (tester) async {
      when(() => bloc.state).thenReturn(const DashboardInitial());
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('dashboard_loading')), findsOneWidget);
    });

    testWidgets('affiche le chargement en état DashboardLoading', (tester) async {
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
