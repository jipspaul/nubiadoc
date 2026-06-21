import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/dashboard/dashboard_bloc.dart';
import 'package:app_patient/features/dashboard/dashboard_event.dart';
import 'package:app_patient/features/dashboard/dashboard_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetDashboardSummaryUseCase extends Mock
    implements GetDashboardSummaryUseCase {}

class _MockDashboardBloc extends MockBloc<DashboardEvent, DashboardState>
    implements DashboardBloc {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _summary = DashboardSummary(
  upcomingAppointments: 2,
  documentsToSign: 0,
  pendingPaymentsCents: 0,
  unreadMessages: 1,
  pendingQuestionnaires: 0,
);

DashboardBloc _makeBloc(MockGetDashboardSummaryUseCase uc) =>
    DashboardBloc(getDashboardSummary: uc);

// ---------------------------------------------------------------------------
// Widget helper — tests the BlocBuilder logic without DashboardPage shell
// ---------------------------------------------------------------------------

class _DashboardBody extends StatelessWidget {
  const _DashboardBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardBloc, DashboardState>(
      builder: (context, state) {
        if (state is DashboardError) {
          return NubiaErrorWidget(
            key: const Key('dashboard_error'),
            message: state.message,
            onRetry: () =>
                context.read<DashboardBloc>().add(const DashboardLoadRequested()),
          );
        }
        if (state is DashboardLoaded) {
          return Text(
            key: const Key('dashboard_loaded'),
            'RDV: ${state.summary.upcomingAppointments}',
          );
        }
        return const CircularProgressIndicator(key: Key('dashboard_loading'));
      },
    );
  }
}

Widget _wrap(DashboardBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<DashboardBloc>.value(
        value: bloc,
        child: const Scaffold(body: _DashboardBody()),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(const DashboardLoadRequested());
  });

  late MockGetDashboardSummaryUseCase mockUc;

  setUp(() {
    mockUc = MockGetDashboardSummaryUseCase();
  });

  group('DashboardBloc', () {
    blocTest<DashboardBloc, DashboardState>(
      'émet [Loading, Loaded] quand getDashboardSummary réussit',
      build: () {
        when(() => mockUc())
            .thenAnswer((_) async => const Right(_summary));
        return _makeBloc(mockUc);
      },
      act: (bloc) => bloc.add(const DashboardLoadRequested()),
      expect: () => [
        const DashboardLoading(),
        isA<DashboardLoaded>().having(
          (s) => s.summary.upcomingAppointments,
          'upcomingAppointments',
          2,
        ),
      ],
    );

    blocTest<DashboardBloc, DashboardState>(
      'émet [Loading, Error] quand getDashboardSummary échoue',
      build: () {
        when(() => mockUc()).thenAnswer(
          (_) async => const Left(NetworkFailure('Erreur réseau.')),
        );
        return _makeBloc(mockUc);
      },
      act: (bloc) => bloc.add(const DashboardLoadRequested()),
      expect: () => [
        const DashboardLoading(),
        isA<DashboardError>()
            .having((s) => s.message, 'message', 'Erreur réseau.'),
      ],
    );
  });

  group('DashboardPage widget', () {
    testWidgets('affiche NubiaErrorWidget en état DashboardError',
        (tester) async {
      when(() => mockUc()).thenAnswer(
        (_) async => const Left(NetworkFailure('Erreur réseau.')),
      );
      final bloc = _makeBloc(mockUc)..add(const DashboardLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dashboard_error')), findsOneWidget);
      expect(find.text('Erreur réseau.'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('tap Réessayer dispatch DashboardLoadRequested',
        (tester) async {
      final mockBloc = _MockDashboardBloc();
      when(() => mockBloc.state)
          .thenReturn(const DashboardError('Erreur réseau.'));
      when(() => mockBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(_wrap(mockBloc));

      await tester.tap(find.text('Réessayer'));

      verify(() => mockBloc.add(const DashboardLoadRequested())).called(1);
    });
  });
}
