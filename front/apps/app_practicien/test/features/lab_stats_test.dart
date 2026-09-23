//! Tests : `LabStatsPage`/`LabStatsCubit` (#7163, DP-F19.c) — coût labo / CA
//! patient / marge du mois courant, agrégés par laboratoire et par
//! praticien.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/lab_work/lab_stats_cubit.dart';
import 'package:app_practicien/features/lab_work/lab_stats_page.dart';

class MockLabStatsCubit extends MockCubit<LabStatsState>
    implements LabStatsCubit {}

const _stats = LabStats(
  periodMonth: '2026-09-01',
  totalLabCostCents: 45000,
  totalPatientRevenueCents: 75000,
  totalMarginCents: 30000,
  byAct: [],
  byPractitioner: [
    LabStatByPractitioner(
      practitionerId: 'practitioner-1',
      practitionerName: 'Dr Martin',
      orderCount: 2,
      labCostCents: 45000,
      patientRevenueCents: 75000,
      marginCents: 30000,
    ),
  ],
  byLab: [
    LabStatByLab(
      labName: 'Labo Dentaire Alpha',
      orderCount: 2,
      labCostCents: 45000,
      patientRevenueCents: 75000,
      marginCents: 30000,
    ),
  ],
);

Widget _wrap(LabStatsCubit cubit) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<LabStatsCubit>.value(
        value: cubit,
        child: const LabStatsPage(),
      ),
    );

void main() {
  group('LabStatsPage (widget)', () {
    testWidgets('le chargement affiche un spinner centré', (tester) async {
      final cubit = MockLabStatsCubit();
      when(() => cubit.state).thenReturn(const LabStatsLoading());
      await tester.pumpWidget(_wrap(cubit));

      expect(find.byKey(const Key('lab_stats_loading')), findsOneWidget);
    });

    testWidgets('une erreur affiche NubiaErrorWidget avec le message',
        (tester) async {
      final cubit = MockLabStatsCubit();
      when(() => cubit.state)
          .thenReturn(const LabStatsError('Erreur réseau'));
      await tester.pumpWidget(_wrap(cubit));

      expect(find.byKey(const Key('lab_stats_error')), findsOneWidget);
      expect(find.text('Erreur réseau'), findsOneWidget);
    });

    testWidgets(
        'les stats chargées affichent les totaux coût/CA/marge et le '
        'détail par laboratoire et par praticien', (tester) async {
      final cubit = MockLabStatsCubit();
      when(() => cubit.state).thenReturn(const LabStatsLoaded(_stats));
      await tester.pumpWidget(_wrap(cubit));

      expect(
        find.descendant(
          of: find.byKey(const Key('lab_stats_total_cost')),
          matching: find.text(NubiaMoney.formatCents(45000)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('lab_stats_total_revenue')),
          matching: find.text(NubiaMoney.formatCents(75000)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('lab_stats_total_margin')),
          matching: find.text(NubiaMoney.formatCents(30000)),
        ),
        findsOneWidget,
      );

      expect(
        find.byKey(const Key('lab_stats_by_lab_Labo Dentaire Alpha')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const Key('lab_stats_by_practitioner_practitioner-1'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'sans bon sur la période, les listes par labo/praticien affichent '
        'un état vide', (tester) async {
      final cubit = MockLabStatsCubit();
      when(() => cubit.state).thenReturn(const LabStatsLoaded(
        LabStats(
          periodMonth: '2026-09-01',
          totalLabCostCents: 0,
          totalPatientRevenueCents: 0,
          totalMarginCents: 0,
          byAct: [],
          byPractitioner: [],
          byLab: [],
        ),
      ));
      await tester.pumpWidget(_wrap(cubit));

      expect(
        find.byKey(const Key('lab_stats_by_lab_empty')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('lab_stats_by_practitioner_empty')),
        findsOneWidget,
      );
    });
  });
}
