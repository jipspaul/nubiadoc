//! Tests widget : `PatientTreatmentPlansBody`/`PatientTreatmentPlanDetailBody`
//! (#4261) — liste (avec/vide) et détail (phases + actes). Golden test
//! indisponible dans ce monorepo (aucune infra golden_toolkit/goldens/
//! n'existe ailleurs) — substitué par ces tests widget standard.
//!
//! `MockBloc`/`MockCubit` (état fixé directement) — pas de `bloc.close()`
//! sur un Bloc/Cubit injecté via `BlocProvider.value` dans un test widget
//! (piège documenté dans `stock_inventory_test.dart`, app_practicien —
//! `.value` ne prend pas possession du cycle de vie, un `close()` explicite
//! y bloque indéfiniment).

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_patient/features/treatment_plans/treatment_plan_detail_page.dart';
import 'package:app_patient/features/treatment_plans/treatment_plans_bloc.dart';
import 'package:app_patient/features/treatment_plans/treatment_plans_page.dart';

class MockPatientTreatmentPlansBloc
    extends MockBloc<PatientTreatmentPlansEvent, PatientTreatmentPlansState>
    implements PatientTreatmentPlansBloc {}

class MockPatientTreatmentPlanDetailCubit
    extends MockCubit<PatientTreatmentPlanDetailState>
    implements PatientTreatmentPlanDetailCubit {}

const _plan = PatientTreatmentPlan(
  id: 'plan-1',
  title: 'Réhabilitation implantaire',
  status: 'in_progress',
);

const _planDetail = PatientTreatmentPlan(
  id: 'plan-1',
  title: 'Réhabilitation implantaire',
  status: 'in_progress',
  totalCostCents: 206000,
  remainingCents: 61800,
  amoPartCents: 40000,
  amcPartCents: 104200,
  phases: [
    PatientTreatmentPlanPhase(
      id: 'phase-1',
      position: 1,
      title: 'Phase 1 · Extraction',
      status: 'done',
      items: [
        PatientTreatmentPlanItem(
          label: 'Extraction 26',
          ccamCode: 'HBGD036',
          unitAmountCents: 8000,
          amoPartCents: 5600,
          amcPartCents: 2400,
        ),
      ],
    ),
    PatientTreatmentPlanPhase(
      id: 'phase-2',
      position: 2,
      title: 'Phase 2 · Implant',
      status: 'requested',
    ),
  ],
);

/// Variante avec un devis en attente d'accord sur la phase 2 — bandeau
/// warning + CTA « Consulter et signer le devis » (#5300).
final _planWithPendingQuote = PatientTreatmentPlan(
  id: 'plan-1',
  title: 'Réhabilitation implantaire',
  status: 'in_progress',
  phases: [
    _planDetail.phases[0],
    PatientTreatmentPlanPhase(
      id: 'phase-2',
      position: 2,
      title: 'Phase 2 · Implant',
      status: 'requested',
      pendingQuoteId: 'quote-42',
      pendingQuoteSentAt: DateTime.utc(2026, 8, 9),
    ),
  ],
);

void main() {
  group('PatientTreatmentPlansBody (liste)', () {
    testWidgets('liste avec plans — affiche une ligne par plan',
        (tester) async {
      final bloc = MockPatientTreatmentPlansBloc();
      when(() => bloc.state)
          .thenReturn(const PatientTreatmentPlansLoaded([_plan]));

      await tester.pumpApp(
        BlocProvider<PatientTreatmentPlansBloc>.value(
          value: bloc,
          child: const PatientTreatmentPlansBody(),
        ),
      );

      expect(find.byKey(const Key('treatment_plans_loaded')), findsOneWidget);
      expect(find.byKey(const Key('treatment_plan_plan-1')), findsOneWidget);
      expect(find.text('Réhabilitation implantaire'), findsOneWidget);
    });

    testWidgets('liste vide — état vide affiché', (tester) async {
      final bloc = MockPatientTreatmentPlansBloc();
      when(() => bloc.state).thenReturn(const PatientTreatmentPlansLoaded([]));

      await tester.pumpApp(
        BlocProvider<PatientTreatmentPlansBloc>.value(
          value: bloc,
          child: const PatientTreatmentPlansBody(),
        ),
      );

      expect(find.byKey(const Key('treatment_plans_empty')), findsOneWidget);
    });
  });

  group('PatientTreatmentPlanDetailBody (détail)', () {
    testWidgets('affiche les phases avec leurs actes et le coût total',
        (tester) async {
      final cubit = MockPatientTreatmentPlanDetailCubit();
      when(() => cubit.state)
          .thenReturn(const PatientTreatmentPlanDetailLoaded(_planDetail));

      await tester.pumpApp(
        BlocProvider<PatientTreatmentPlanDetailCubit>.value(
          value: cubit,
          child: const PatientTreatmentPlanDetailBody(),
        ),
      );

      expect(
        find.byKey(const Key('treatment_plan_detail_loaded')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('treatment_plan_phase_phase-1')),
          findsOneWidget);
      expect(find.byKey(const Key('treatment_plan_phase_phase-2')),
          findsOneWidget);
      expect(find.text('Extraction 26'), findsOneWidget);
      expect(find.text('2 060 €'), findsOneWidget);
    });

    testWidgets(
        'bloc « Coût de votre plan » — décompose réglé/engagé/en attente '
        'et retire l\'AmountHeader (#5301)', (tester) async {
      final cubit = MockPatientTreatmentPlanDetailCubit();
      when(() => cubit.state)
          .thenReturn(const PatientTreatmentPlanDetailLoaded(_planDetail));

      await tester.pumpApp(
        BlocProvider<PatientTreatmentPlanDetailCubit>.value(
          value: cubit,
          child: const PatientTreatmentPlanDetailBody(),
        ),
      );

      expect(find.byType(AmountHeader), findsNothing);
      expect(find.byKey(const Key('plan_cost_block')), findsOneWidget);
      expect(find.text('CE QUE CELA REPRÉSENTE'), findsOneWidget);
      expect(find.text('Coût de votre plan'), findsOneWidget);
      expect(find.text('Total du plan de soins'), findsOneWidget);
      expect(find.text('Déjà réglé'), findsOneWidget);
      expect(find.text('Engagé (devis signé)'), findsOneWidget);
      expect(find.text('En attente de votre accord'), findsOneWidget);
      // Fixture : phase-1 (done) contient un seul acte de 8 000 c → réglé.
      expect(
        find.descendant(
          of: find.byKey(const Key('plan_cost_block')),
          matching: find.text('80 €'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'affiche l\'encart montants estimés après le bloc financier (#5302)',
        (tester) async {
      final cubit = MockPatientTreatmentPlanDetailCubit();
      when(() => cubit.state)
          .thenReturn(const PatientTreatmentPlanDetailLoaded(_planDetail));

      await tester.pumpApp(
        BlocProvider<PatientTreatmentPlanDetailCubit>.value(
          value: cubit,
          child: const PatientTreatmentPlanDetailBody(),
        ),
      );

      expect(
        find.byKey(const Key('treatment_plan_estimated_amounts_notice')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('treatment_plan_estimated_amounts_notice')),
          matching: find.byIcon(Icons.info),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Les montants en attente sont des estimations de votre '
          'praticien. Le reste à votre charge définitif figure sur le '
          'devis, après calcul des remboursements de l\'Assurance '
          'Maladie et de votre mutuelle.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'phase sans devis en attente — pas de bandeau ni de CTA (#5300)',
        (tester) async {
      final cubit = MockPatientTreatmentPlanDetailCubit();
      when(() => cubit.state)
          .thenReturn(const PatientTreatmentPlanDetailLoaded(_planDetail));

      await tester.pumpApp(
        BlocProvider<PatientTreatmentPlanDetailCubit>.value(
          value: cubit,
          child: const PatientTreatmentPlanDetailBody(),
        ),
      );

      expect(find.byKey(const Key('phase_phase-2_pending_quote_banner')),
          findsNothing);
      expect(
          find.byKey(const Key('phase_phase-2_quote_cta')), findsNothing);
    });

    testWidgets(
        'phase avec devis en attente — bandeau warning + CTA (#5300)',
        (tester) async {
      final cubit = MockPatientTreatmentPlanDetailCubit();
      when(() => cubit.state).thenReturn(
          PatientTreatmentPlanDetailLoaded(_planWithPendingQuote));

      await tester.pumpApp(
        BlocProvider<PatientTreatmentPlanDetailCubit>.value(
          value: cubit,
          child: const PatientTreatmentPlanDetailBody(),
        ),
      );

      expect(find.byKey(const Key('phase_phase-2_pending_quote_banner')),
          findsOneWidget);
      expect(find.byKey(const Key('phase_phase-2_quote_cta')), findsOneWidget);
      expect(find.byIcon(Icons.description), findsOneWidget);
      expect(find.byIcon(Icons.draw), findsOneWidget);
      expect(find.text('Consulter et signer le devis'), findsOneWidget);

      final textSpan = tester
          .widget<Text>(find.descendant(
            of: find.byKey(const Key('phase_phase-2_pending_quote_banner')),
            matching: find.byType(Text),
          ))
          .textSpan as TextSpan;
      expect(textSpan.toPlainText(),
          'Un devis vous a été envoyé le 9 août. Cette étape ne peut pas '
          'être programmée avant votre accord.');
      final firstSpan = textSpan.children!.first as TextSpan;
      expect(firstSpan.style?.fontWeight, FontWeight.bold);
    });

    testWidgets(
        'CTA « Consulter et signer le devis » navigue vers l\'écran du '
        'devis correspondant (#5300)', (tester) async {
      final cubit = MockPatientTreatmentPlanDetailCubit();
      when(() => cubit.state).thenReturn(
          PatientTreatmentPlanDetailLoaded(_planWithPendingQuote));

      String? pushedLocation;
      final router = GoRouter(
        initialLocation: '/treatment-plans/plan-1',
        routes: [
          GoRoute(
            path: '/treatment-plans/plan-1',
            builder: (_, __) =>
                BlocProvider<PatientTreatmentPlanDetailCubit>.value(
              value: cubit,
              child: const PatientTreatmentPlanDetailBody(),
            ),
          ),
          GoRoute(
            path: '/financial',
            builder: (_, state) {
              pushedLocation = state.uri.toString();
              return const Scaffold(body: Text('financial'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();

      await tester
          .ensureVisible(find.byKey(const Key('phase_phase-2_quote_cta')));
      await tester.tap(find.byKey(const Key('phase_phase-2_quote_cta')));
      await tester.pumpAndSettle();

      expect(pushedLocation, '/financial?id=quote-42');
    });
  });
}
