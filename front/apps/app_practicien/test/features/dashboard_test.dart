import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/dashboard/dashboard_bloc.dart';
import 'package:app_practicien/features/dashboard/dashboard_event.dart';
import 'package:app_practicien/features/dashboard/dashboard_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetProDashboardSummaryUseCase extends Mock
    implements GetProDashboardSummaryUseCase {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _summary = ProDashboardSummary(
  todayAppointments: 5,
  waitingRoomCount: 2,
  unreadMessages: 3,
  pendingConfirmations: 1,
);

DashboardBloc _makeBloc(MockGetProDashboardSummaryUseCase uc) =>
    DashboardBloc(getSummary: uc);

// ---------------------------------------------------------------------------
// Widget helper
// ---------------------------------------------------------------------------

Widget _wrap(DashboardBloc bloc, Widget child) => MaterialApp(
      home: BlocProvider.value(
        value: bloc,
        child: Scaffold(body: child),
      ),
    );

class _DashboardBody extends StatelessWidget {
  const _DashboardBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardBloc, DashboardState>(
      builder: (context, state) {
        if (state is DashboardInitial || state is DashboardLoading) {
          return const Center(
            key: Key('dashboard_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is DashboardError) {
          return Center(
            key: const Key('dashboard_error'),
            child: Text(state.message),
          );
        }
        if (state is DashboardLoaded) {
          return Column(
            key: const Key('dashboard_loaded'),
            children: [
              Text('RDV: ${state.summary.todayAppointments}'),
              Text('Attente: ${state.summary.waitingRoomCount}'),
              Text('Messages: ${state.summary.unreadMessages}'),
              Text('Confirmations: ${state.summary.pendingConfirmations}'),
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
  group('DashboardBloc', () {
    late MockGetProDashboardSummaryUseCase mockUc;

    setUp(() {
      mockUc = MockGetProDashboardSummaryUseCase();
    });

    blocTest<DashboardBloc, DashboardState>(
      'émet Loading puis Loaded avec le résumé',
      build: () {
        when(() => mockUc()).thenAnswer((_) async => Right(_summary));
        return _makeBloc(mockUc);
      },
      act: (bloc) => bloc.add(const DashboardLoadRequested()),
      expect: () => [
        const DashboardLoading(),
        DashboardLoaded(_summary),
      ],
    );

    blocTest<DashboardBloc, DashboardState>(
      'émet Loading puis Error en cas d\'échec',
      build: () {
        when(() => mockUc()).thenAnswer(
          (_) async => const Left(ServerFailure(message: 'Erreur réseau')),
        );
        return _makeBloc(mockUc);
      },
      act: (bloc) => bloc.add(const DashboardLoadRequested()),
      expect: () => [
        const DashboardLoading(),
        const DashboardError('Erreur réseau'),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // Widget tests
  // ---------------------------------------------------------------------------

  group('DashboardPage widget', () {
    late MockGetProDashboardSummaryUseCase mockUc;

    setUp(() {
      mockUc = MockGetProDashboardSummaryUseCase();
    });

    testWidgets('affiche le chargement en état Loading', (tester) async {
      final bloc = _makeBloc(mockUc);
      await tester.pumpWidget(_wrap(bloc, const _DashboardBody()));
      expect(find.byKey(const Key('dashboard_loading')), findsOneWidget);
    });

    testWidgets('affiche les statistiques en état Loaded', (tester) async {
      when(() => mockUc()).thenAnswer((_) async => Right(_summary));
      final bloc = _makeBloc(mockUc)..add(const DashboardLoadRequested());
      await tester.pumpWidget(_wrap(bloc, const _DashboardBody()));
      await tester.pump();
      expect(find.byKey(const Key('dashboard_loaded')), findsOneWidget);
      expect(find.text('RDV: 5'), findsOneWidget);
      expect(find.text('Attente: 2'), findsOneWidget);
      expect(find.text('Messages: 3'), findsOneWidget);
    });

    testWidgets('affiche une erreur en état Error', (tester) async {
      when(() => mockUc()).thenAnswer(
        (_) async => const Left(ServerFailure(message: 'Erreur')),
      );
      final bloc = _makeBloc(mockUc)..add(const DashboardLoadRequested());
      await tester.pumpWidget(_wrap(bloc, const _DashboardBody()));
      await tester.pump();
      expect(find.byKey(const Key('dashboard_error')), findsOneWidget);
      expect(find.text('Erreur'), findsOneWidget);
    });
  });
}
