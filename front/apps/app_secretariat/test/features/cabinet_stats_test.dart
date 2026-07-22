//! Tests : `CabinetStatsBody`/`CabinetStatsBloc` (#4153) — affichage des KPI
//! (CA encaissé, reste à encaisser, taux de transformation, activité par
//! praticien) à partir des 2 routes stats mockées. Golden test indisponible
//! dans ce monorepo (aucune infra golden_toolkit/goldens/ n'existe ailleurs)
//! — substitué par ces tests widget standard couvrant la même assertion
//! comportementale.
//!
//! `MockCabinetStatsBloc` (état fixé directement, comme `devis_test.dart` /
//! `stock_inventory_test.dart`) — évite de faire tourner un vrai Bloc dans un
//! test widget. Pas de `bloc.close()` sur un Bloc injecté via
//! `BlocProvider.value` (piège documenté dans `stock_inventory_test.dart`,
//! app_practicien).

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/cabinet_stats/cabinet_stats_bloc.dart';
import 'package:app_secretariat/features/cabinet_stats/cabinet_stats_event.dart';
import 'package:app_secretariat/features/cabinet_stats/cabinet_stats_page.dart';
import 'package:app_secretariat/features/cabinet_stats/cabinet_stats_state.dart';

class MockCabinetStatsBloc
    extends MockBloc<CabinetStatsEvent, CabinetStatsState>
    implements CabinetStatsBloc {}

const _billing = CabinetBillingStats(
  revenueCollectedCents: 450000,
  outstandingCents: 12000,
  conversionRate: 0.75,
  signedCount: 15,
  sentTotal: 20,
);

const _activity = [
  CabinetActivityStat(
    practitionerId: 'prac-1',
    practitionerName: 'Dr Martin',
    ccamCode: 'HBLD001',
    label: 'Détartrage',
    actCount: 10,
    totalAmountCents: 75000,
  ),
  CabinetActivityStat(
    practitionerId: 'prac-1',
    practitionerName: 'Dr Martin',
    ccamCode: 'HBGD047',
    label: 'Avulsion',
    actCount: 2,
    totalAmountCents: 20000,
  ),
  CabinetActivityStat(
    practitionerId: 'prac-2',
    practitionerName: 'Dr Petit',
    ccamCode: 'HBLD001',
    label: 'Détartrage',
    actCount: 5,
    totalAmountCents: 37500,
  ),
];

Widget _wrap(CabinetStatsBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<CabinetStatsBloc>.value(
        value: bloc,
        child: const CabinetStatsBody(),
      ),
    );

void main() {
  testWidgets('affiche les KPI de facturation et l\'activité par praticien',
      (tester) async {
    final bloc = MockCabinetStatsBloc();
    when(() => bloc.state)
        .thenReturn(const CabinetStatsLoaded(_activity, _billing));
    await tester.pumpWidget(_wrap(bloc));

    expect(find.byKey(const Key('stat_revenue_collected')), findsOneWidget);
    expect(find.text('4500.00 €'), findsOneWidget);
    expect(find.text('120.00 €'), findsOneWidget);
    expect(find.text('75 %'), findsOneWidget);
    expect(find.text('15 / 20'), findsOneWidget);

    // Activité agrégée par praticien (10+2 actes pour Dr Martin, 5 pour Dr Petit).
    expect(
      find.byKey(const Key('practitioner_activity_prac-1')),
      findsOneWidget,
    );
    expect(find.text('12 actes · 950.00 €'), findsOneWidget);
    expect(
      find.byKey(const Key('practitioner_activity_prac-2')),
      findsOneWidget,
    );
    expect(find.text('5 actes · 375.00 €'), findsOneWidget);
  });

  testWidgets('taux de transformation absent (aucun devis envoyé) → tiret',
      (tester) async {
    final bloc = MockCabinetStatsBloc();
    when(() => bloc.state).thenReturn(const CabinetStatsLoaded(
      [],
      CabinetBillingStats(
        revenueCollectedCents: 0,
        outstandingCents: 0,
        signedCount: 0,
        sentTotal: 0,
      ),
    ));
    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('—'), findsOneWidget);
    expect(
      find.byKey(const Key('cabinet_stats_activity_empty')),
      findsOneWidget,
    );
  });
}
