//! Tests cubit (#6780, QA-20260909-1) : un chart « vierge » (date `null`,
//! contrat API pour un patient sans odontogramme / sans bilan) doit mener à
//! l'état `Loaded` — jamais à `Error` — avec le drapeau `isBlank` qui pilote
//! l'appel à l'action de l'écran.

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/dental_chart/dental_chart_cubit.dart';
import 'package:app_practicien/features/periodontal_chart/periodontal_chart_cubit.dart';

class _MockGetDentalChart extends Mock implements GetDentalChartUseCase {}

class _MockPutDentalChart extends Mock implements PutDentalChartUseCase {}

class _MockGetPeriodontalChart extends Mock
    implements GetPeriodontalChartUseCase {}

class _MockPutPeriodontalChart extends Mock
    implements PutPeriodontalChartUseCase {}

void main() {
  group('DentalChartCubit — patient neuf (#6780)', () {
    late _MockGetDentalChart getChart;
    late _MockPutDentalChart putChart;

    setUp(() {
      getChart = _MockGetDentalChart();
      putChart = _MockPutDentalChart();
    });

    blocTest<DentalChartCubit, DentalChartState>(
      'chart sans updatedAt → Loaded vierge (isBlank), pas Error',
      build: () {
        when(() => getChart('pat-1')).thenAnswer(
          (_) async => const Right(DentalChart(teeth: {})),
        );
        return DentalChartCubit(
          patientId: 'pat-1',
          getDentalChart: getChart,
          putDentalChart: putChart,
        );
      },
      expect: () => [
        const DentalChartLoaded(teeth: {}, isBlank: true),
      ],
    );

    blocTest<DentalChartCubit, DentalChartState>(
      'chart daté → Loaded non vierge',
      build: () {
        when(() => getChart('pat-1')).thenAnswer(
          (_) async => Right(
            DentalChart(
              teeth: const {'11': ToothState(status: 'carie')},
              updatedAt: DateTime(2026, 9, 9),
            ),
          ),
        );
        return DentalChartCubit(
          patientId: 'pat-1',
          getDentalChart: getChart,
          putDentalChart: putChart,
        );
      },
      expect: () => [
        const DentalChartLoaded(
          teeth: {'11': ToothState(status: 'carie')},
        ),
      ],
    );

    blocTest<DentalChartCubit, DentalChartState>(
      'premier save() : le PUT renvoie un chart daté → isBlank retombe',
      build: () {
        when(() => getChart('pat-1')).thenAnswer(
          (_) async => const Right(DentalChart(teeth: {})),
        );
        when(() => putChart('pat-1', any())).thenAnswer(
          (_) async => Right(
            DentalChart(
              teeth: const {'11': ToothState(status: 'sain')},
              updatedAt: DateTime(2026, 9, 9),
            ),
          ),
        );
        return DentalChartCubit(
          patientId: 'pat-1',
          getDentalChart: getChart,
          putDentalChart: putChart,
        );
      },
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        cubit.setToothStatus('11', 'sain');
        await cubit.save();
      },
      skip: 1,
      expect: () => [
        const DentalChartLoaded(
          teeth: {'11': ToothState(status: 'sain')},
          dirty: true,
          isBlank: true,
        ),
        const DentalChartLoaded(
          teeth: {'11': ToothState(status: 'sain')},
          dirty: true,
          saving: true,
          isBlank: true,
        ),
        const DentalChartLoaded(
          teeth: {'11': ToothState(status: 'sain')},
        ),
      ],
    );
  });

  group('PeriodontalChartCubit — patient neuf (#6780)', () {
    late _MockGetPeriodontalChart getChart;
    late _MockPutPeriodontalChart putChart;

    setUp(() {
      getChart = _MockGetPeriodontalChart();
      putChart = _MockPutPeriodontalChart();
    });

    blocTest<PeriodontalChartCubit, PeriodontalChartState>(
      'bilan sans measuredAt → Loaded vierge (isBlank), pas Error',
      build: () {
        when(() => getChart('pat-1')).thenAnswer(
          (_) async => const Right(PeriodontalChart(sites: {}, indices: {})),
        );
        return PeriodontalChartCubit(
          patientId: 'pat-1',
          getPeriodontalChart: getChart,
          putPeriodontalChart: putChart,
        );
      },
      expect: () => [
        const PeriodontalChartLoaded(sites: {}, indices: {}, isBlank: true),
      ],
    );

    blocTest<PeriodontalChartCubit, PeriodontalChartState>(
      'premier save() : le PUT renvoie un bilan daté → isBlank retombe',
      build: () {
        when(() => getChart('pat-1')).thenAnswer(
          (_) async => const Right(PeriodontalChart(sites: {}, indices: {})),
        );
        when(() => putChart('pat-1', any(), any())).thenAnswer(
          (_) async => Right(
            PeriodontalChart(
              sites: const {'11': ToothSiteDepths(mv: 3)},
              indices: const {},
              measuredAt: DateTime(2026, 9, 9),
            ),
          ),
        );
        return PeriodontalChartCubit(
          patientId: 'pat-1',
          getPeriodontalChart: getChart,
          putPeriodontalChart: putChart,
        );
      },
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        cubit.setToothSite('11', const ToothSiteDepths(mv: 3));
        await cubit.save();
      },
      skip: 1,
      expect: () => [
        const PeriodontalChartLoaded(
          sites: {'11': ToothSiteDepths(mv: 3)},
          indices: {},
          dirty: true,
          isBlank: true,
        ),
        const PeriodontalChartLoaded(
          sites: {'11': ToothSiteDepths(mv: 3)},
          indices: {},
          dirty: true,
          saving: true,
          isBlank: true,
        ),
        const PeriodontalChartLoaded(
          sites: {'11': ToothSiteDepths(mv: 3)},
          indices: {},
        ),
      ],
    );
  });
}
