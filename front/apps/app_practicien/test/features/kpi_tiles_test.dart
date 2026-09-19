import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/dashboard/kpi_tiles_cubit.dart';
import 'package:app_practicien/features/dashboard/kpi_tiles_row.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetMyKpisUseCase extends Mock implements GetMyKpisUseCase {}

class MockKpiTilesCubit extends MockCubit<KpiTilesState>
    implements KpiTilesCubit {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _cabinetA = CabinetKpiSummary(
  cabinetId: 'cab-a',
  cabinetName: 'Cabinet Centre',
  today: PractitionerKpiAmounts(billedCents: 8000, collectedCents: 6000),
  month: PractitionerKpiAmounts(billedCents: 250000, collectedCents: 200000),
  appointmentsToday: 4,
  pendingReminders: 1,
  occupancyRate: 0.7,
  objectiveTargetCents: 300000,
  objectiveAchievedPct: 250000 / 300000,
);

const _cabinetB = CabinetKpiSummary(
  cabinetId: 'cab-b',
  cabinetName: 'Cabinet Nord',
  today: PractitionerKpiAmounts(billedCents: 7000, collectedCents: 5000),
  month: PractitionerKpiAmounts(billedCents: 200000, collectedCents: 150000),
  appointmentsToday: 2,
  pendingReminders: 2,
  occupancyRate: 0.9,
  objectiveTargetCents: 300000,
  objectiveAchievedPct: 200000 / 300000,
);

PractitionerKpis _kpis({
  int? objectiveTargetCents = 600000,
  double? objectiveAchievedPct = 0.75,
  double? occupancyRate = 0.8,
  List<CabinetKpiSummary> byCabinet = const [],
}) =>
    PractitionerKpis(
      periodMonth: '2026-09-01',
      today: const PractitionerKpiAmounts(
        billedCents: 15000,
        collectedCents: 12000,
      ),
      month: const PractitionerKpiAmounts(
        billedCents: 450000,
        collectedCents: 380000,
      ),
      appointmentsToday: 6,
      pendingReminders: 3,
      occupancyRate: occupancyRate,
      objectiveTargetCents: objectiveTargetCents,
      objectiveAchievedPct: objectiveAchievedPct,
      byCabinet: byCabinet,
    );

// ---------------------------------------------------------------------------
// Widget helper
// ---------------------------------------------------------------------------

Widget _wrap(KpiTilesCubit cubit) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(
        body: BlocProvider<KpiTilesCubit>.value(
          value: cubit,
          child: const KpiTilesRow(),
        ),
      ),
    );

void main() {
  // ---------------------------------------------------------------------------
  // KpiTilesCubit
  // ---------------------------------------------------------------------------

  group('KpiTilesCubit', () {
    late MockGetMyKpisUseCase mockUc;

    setUp(() {
      mockUc = MockGetMyKpisUseCase();
    });

    blocTest<KpiTilesCubit, KpiTilesState>(
      'load() émet Loading puis Loaded avec les KPI',
      build: () {
        when(() => mockUc()).thenAnswer((_) async => Right(_kpis()));
        return KpiTilesCubit(getMyKpis: mockUc);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const KpiTilesLoading(),
        KpiTilesLoaded(kpis: _kpis()),
      ],
    );

    blocTest<KpiTilesCubit, KpiTilesState>(
      'load() émet Loading puis Error en cas d\'échec',
      build: () {
        when(() => mockUc()).thenAnswer(
          (_) async => const Left(ServerFailure(message: 'Erreur réseau')),
        );
        return KpiTilesCubit(getMyKpis: mockUc);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const KpiTilesLoading(),
        const KpiTilesError('Erreur réseau'),
      ],
    );

    blocTest<KpiTilesCubit, KpiTilesState>(
      'selectCabinet() bascule vers un cabinet puis revient à l\'agrégat',
      build: () => KpiTilesCubit(getMyKpis: mockUc),
      seed: () =>
          KpiTilesLoaded(kpis: _kpis(byCabinet: const [_cabinetA, _cabinetB])),
      act: (cubit) {
        cubit.selectCabinet('cab-b');
        cubit.selectCabinet(null);
      },
      expect: () => [
        KpiTilesLoaded(
          kpis: _kpis(byCabinet: const [_cabinetA, _cabinetB]),
          selectedCabinetId: 'cab-b',
        ),
        KpiTilesLoaded(kpis: _kpis(byCabinet: const [_cabinetA, _cabinetB])),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // KpiTilesRow widget
  // ---------------------------------------------------------------------------

  group('KpiTilesRow widget', () {
    late MockKpiTilesCubit mockCubit;

    setUp(() {
      mockCubit = MockKpiTilesCubit();
    });

    testWidgets('affiche un squelette pendant le chargement', (tester) async {
      when(() => mockCubit.state).thenReturn(const KpiTilesLoading());
      await tester.pumpWidget(_wrap(mockCubit));

      expect(find.byKey(const Key('kpi_tiles_loading')), findsOneWidget);
    });

    testWidgets('affiche une erreur avec un bouton réessayer', (tester) async {
      when(() => mockCubit.state)
          .thenReturn(const KpiTilesError('Erreur réseau'));
      when(() => mockCubit.load()).thenAnswer((_) async {});
      await tester.pumpWidget(_wrap(mockCubit));

      expect(find.text('Erreur réseau'), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      verify(() => mockCubit.load()).called(1);
    });

    testWidgets(
        'affiche les quatre tuiles avec les données réelles (CA, RDV, '
        'rappels, occupation)', (tester) async {
      when(() => mockCubit.state)
          .thenReturn(KpiTilesLoaded(kpis: _kpis()));
      await tester.pumpWidget(_wrap(mockCubit));

      expect(find.byKey(const Key('kpi_tile_revenue')), findsOneWidget);
      expect(find.byKey(const Key('kpi_tile_appointments')), findsOneWidget);
      expect(find.byKey(const Key('kpi_tile_reminders')), findsOneWidget);
      expect(find.byKey(const Key('kpi_tile_occupancy')), findsOneWidget);

      // CA du mois (450 000 c) vs objectif (600 000 c) → 75 %.
      expect(find.text('4 500 €'), findsOneWidget);
      expect(find.byKey(const Key('kpi_revenue_pct')), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);

      expect(find.text('6'), findsOneWidget); // RDV aujourd'hui
      expect(find.text('3'), findsOneWidget); // Rappels en attente
      expect(find.text('80%'), findsOneWidget); // Occupation (0.8)

      expect(find.byKey(const Key('kpi_cabinet_selector')), findsNothing);
    });

    testWidgets(
        'sans objectif défini, affiche le CA seul sans jauge trompeuse',
        (tester) async {
      when(() => mockCubit.state).thenReturn(
        KpiTilesLoaded(
          kpis: _kpis(objectiveTargetCents: null, objectiveAchievedPct: null),
        ),
      );
      await tester.pumpWidget(_wrap(mockCubit));

      expect(
        find.text('CA du mois · objectif non défini'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('kpi_revenue_pct')), findsNothing);

      final gauge = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('kpi_revenue_gauge')),
      );
      expect(gauge.value, 0);
    });

    testWidgets('taux d\'occupation indisponible affiche un tiret',
        (tester) async {
      when(() => mockCubit.state).thenReturn(
        KpiTilesLoaded(kpis: _kpis(occupancyRate: null)),
      );
      await tester.pumpWidget(_wrap(mockCubit));

      expect(find.text('—'), findsOneWidget);
    });

    testWidgets(
        'n\'affiche pas le sélecteur de centre pour un praticien mono-cabinet',
        (tester) async {
      when(() => mockCubit.state).thenReturn(
        KpiTilesLoaded(kpis: _kpis(byCabinet: const [_cabinetA])),
      );
      await tester.pumpWidget(_wrap(mockCubit));

      expect(find.byKey(const Key('kpi_cabinet_selector')), findsNothing);
    });

    testWidgets(
        'affiche le sélecteur de centre pour un praticien multi-cabinet',
        (tester) async {
      when(() => mockCubit.state).thenReturn(
        KpiTilesLoaded(
          kpis: _kpis(byCabinet: const [_cabinetA, _cabinetB]),
        ),
      );
      await tester.pumpWidget(_wrap(mockCubit));

      expect(find.byKey(const Key('kpi_cabinet_selector')), findsOneWidget);
      expect(find.text('Tous les cabinets'), findsOneWidget);
    });

    testWidgets(
        'choisir un centre dans le sélecteur appelle selectCabinet avec son id',
        (tester) async {
      when(() => mockCubit.state).thenReturn(
        KpiTilesLoaded(
          kpis: _kpis(byCabinet: const [_cabinetA, _cabinetB]),
        ),
      );
      when(() => mockCubit.selectCabinet(any())).thenReturn(null);
      await tester.pumpWidget(_wrap(mockCubit));

      await tester.tap(find.byKey(const Key('kpi_cabinet_selector')));
      await tester.pumpAndSettle();

      expect(find.text('Cabinet Nord'), findsWidgets);
      await tester.tap(find.text('Cabinet Nord').last);
      await tester.pumpAndSettle();

      verify(() => mockCubit.selectCabinet('cab-b')).called(1);
    });
  });
}
