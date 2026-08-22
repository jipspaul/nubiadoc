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

const _donePlan = PatientTreatmentPlan(
  id: 'plan-3',
  title: 'Détartrage annuel',
  status: 'done',
);

/// Plan « En cours » avec une prochaine séance programmée — rangée `.nx`
/// en pied de carte (#5289).
final _planWithNextAppointment = PatientTreatmentPlan(
  id: 'plan-1',
  title: 'Réhabilitation implantaire',
  status: 'in_progress',
  nextAppointmentId: 'appt-42',
  nextAppointmentAt: DateTime.utc(2026, 8, 11, 14, 30),
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

/// Plan avec un devis reçu et non signé qui porte sur le plan entier — sa
/// propre carte warning dans la section « À votre décision » de la liste,
/// hors du flux normal (#5291).
final _planWithPendingPlanQuote = PatientTreatmentPlan(
  id: 'plan-2',
  title: 'Prothèse d\'usage — phase 3',
  status: 'proposed',
  pendingQuoteId: 'quote-99',
  pendingQuoteLabel: 'Couronne céramo-métallique sur la dent 26',
  pendingQuoteReceivedAt: DateTime.utc(2026, 8, 9),
  pendingQuotePatientShareCents: 42000,
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

/// Variante avec la phase 2 en cours et un rendez-vous programmé — CTA
/// « Voir mon rendez-vous » (#5299).
const _planWithScheduledAppointment = PatientTreatmentPlan(
  id: 'plan-1',
  title: 'Réhabilitation implantaire',
  status: 'in_progress',
  phases: [
    PatientTreatmentPlanPhase(
      id: 'phase-1',
      position: 1,
      title: 'Phase 1 · Extraction',
      status: 'done',
    ),
    PatientTreatmentPlanPhase(
      id: 'phase-2',
      position: 2,
      title: 'Phase 2 · Implant',
      status: 'in_progress',
      appointmentId: 'appt-42',
    ),
  ],
);

/// Variante avec les trois statuts de couverture financière de phase — bloc
/// `.amt` : réglé, couvert par un devis signé, estimation (#5298).
final _planWithCoverageStates = PatientTreatmentPlan(
  id: 'plan-1',
  title: 'Réhabilitation implantaire',
  status: 'in_progress',
  phases: [
    PatientTreatmentPlanPhase(
      id: 'phase-1',
      position: 1,
      title: 'Assainissement',
      status: 'done',
      description: 'Détartrage complet et soin d\'une carie sur la dent 26.',
      items: const [
        PatientTreatmentPlanItem(
          label: 'Détartrage',
          unitAmountCents: 8242,
          amoPartCents: 0,
          amcPartCents: 0,
        ),
      ],
      appointmentAt: DateTime.utc(2026, 7, 22, 9),
    ),
    PatientTreatmentPlanPhase(
      id: 'phase-2',
      position: 2,
      title: 'Endodontie et reconstitution',
      status: 'in_progress',
      items: const [
        PatientTreatmentPlanItem(
          label: 'Endodontie',
          unitAmountCents: 35350,
          amoPartCents: 0,
          amcPartCents: 0,
        ),
      ],
      appointmentAt: DateTime.now().toUtc(),
    ),
    PatientTreatmentPlanPhase(
      id: 'phase-3',
      position: 3,
      title: 'Prothèse d\'usage',
      status: 'requested',
      items: const [
        PatientTreatmentPlanItem(
          label: 'Couronne',
          unitAmountCents: 120000,
          amoPartCents: 0,
          amcPartCents: 0,
        ),
      ],
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

    testWidgets(
        'liste avec plans — encart d\'information en bas de liste (#5292)',
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

      final notice = find.byKey(const Key('treatment_plans_info_notice'));
      expect(notice, findsOneWidget);
      expect(
        find.descendant(of: notice, matching: find.byIcon(Icons.shield)),
        findsOneWidget,
      );
      expect(
        find.text(
          'Un plan de soins décrit les étapes proposées par votre '
          "praticien. Les montants sont indicatifs tant qu'un devis n'a "
          'pas été signé.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'liste sans devis en attente — pas de section « À votre décision » '
        '(#5291)', (tester) async {
      final bloc = MockPatientTreatmentPlansBloc();
      when(() => bloc.state)
          .thenReturn(const PatientTreatmentPlansLoaded([_plan]));

      await tester.pumpApp(
        BlocProvider<PatientTreatmentPlansBloc>.value(
          value: bloc,
          child: const PatientTreatmentPlansBody(),
        ),
      );

      expect(find.text('À VOTRE DÉCISION'), findsNothing);
      expect(find.byKey(const Key('pending_quote_card_plan-2')), findsNothing);
    });

    testWidgets(
        'plan avec devis reçu et non signé — carte warning dédiée dans la '
        'section « À votre décision », pas de doublon en carte normale '
        '(#5291)', (tester) async {
      final bloc = MockPatientTreatmentPlansBloc();
      when(() => bloc.state).thenReturn(
          PatientTreatmentPlansLoaded([_plan, _planWithPendingPlanQuote]));

      await tester.pumpApp(
        BlocProvider<PatientTreatmentPlansBloc>.value(
          value: bloc,
          child: const PatientTreatmentPlansBody(),
        ),
      );

      expect(find.text('À VOTRE DÉCISION'), findsOneWidget);
      expect(find.text('1 devis en attente'), findsOneWidget);

      final card = find.byKey(const Key('pending_quote_card_plan-2'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(
            of: card, matching: find.text('Prothèse d\'usage — phase 3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('À accepter')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching:
              find.text('Couronne céramo-métallique sur la dent 26'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: card, matching: find.text('Reste à votre charge estimé')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('420 €')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: card, matching: find.text('Devis reçu le 9 août')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Consulter')),
        findsOneWidget,
      );

      // Le plan avec devis en attente ne doit pas aussi apparaître comme
      // carte de plan normale (évite le doublon).
      expect(find.byKey(const Key('treatment_plan_plan-2')), findsNothing);
      // L'autre plan, lui, reste une ligne normale.
      expect(find.byKey(const Key('treatment_plan_plan-1')), findsOneWidget);
    });

    testWidgets(
        'trois sections « En cours » / « À votre décision » / « Terminés », '
        'dans cet ordre, sans doublon (#5290)', (tester) async {
      final bloc = MockPatientTreatmentPlansBloc();
      when(() => bloc.state).thenReturn(PatientTreatmentPlansLoaded(
          [_plan, _planWithPendingPlanQuote, _donePlan]));

      await tester.pumpApp(
        BlocProvider<PatientTreatmentPlansBloc>.value(
          value: bloc,
          child: const PatientTreatmentPlansBody(),
        ),
      );

      expect(find.text('EN COURS'), findsOneWidget);
      expect(find.text('À VOTRE DÉCISION'), findsOneWidget);
      expect(find.text('TERMINÉS'), findsOneWidget);
      expect(find.text('1 devis en attente'), findsOneWidget);

      final headers = [
        tester.getTopLeft(find.text('EN COURS')).dy,
        tester.getTopLeft(find.text('À VOTRE DÉCISION')).dy,
        tester.getTopLeft(find.text('TERMINÉS')).dy,
      ];
      expect(headers, [headers[0], headers[1], headers[2]]..sort());

      expect(find.byKey(const Key('treatment_plan_plan-1')), findsOneWidget);
      expect(find.byKey(const Key('pending_quote_card_plan-2')),
          findsOneWidget);
      expect(find.byKey(const Key('treatment_plan_plan-3')), findsOneWidget);
      // Aucun plan de la section décision ne doit réapparaître ailleurs.
      expect(find.byKey(const Key('treatment_plan_plan-2')), findsNothing);
    });

    testWidgets(
        'section vide non affichée — pas de « TERMINÉS » sans plan terminé '
        '(#5290)', (tester) async {
      final bloc = MockPatientTreatmentPlansBloc();
      when(() => bloc.state)
          .thenReturn(const PatientTreatmentPlansLoaded([_plan]));

      await tester.pumpApp(
        BlocProvider<PatientTreatmentPlansBloc>.value(
          value: bloc,
          child: const PatientTreatmentPlansBody(),
        ),
      );

      expect(find.text('EN COURS'), findsOneWidget);
      expect(find.text('TERMINÉS'), findsNothing);
      expect(find.text('À VOTRE DÉCISION'), findsNothing);
    });

    testWidgets(
        '« Consulter » navigue vers l\'écran du devis correspondant (#5291)',
        (tester) async {
      final bloc = MockPatientTreatmentPlansBloc();
      when(() => bloc.state).thenReturn(
          PatientTreatmentPlansLoaded([_planWithPendingPlanQuote]));

      String? pushedLocation;
      final router = GoRouter(
        initialLocation: '/treatment-plans',
        routes: [
          GoRoute(
            path: '/treatment-plans',
            builder: (_, __) => BlocProvider<PatientTreatmentPlansBloc>.value(
              value: bloc,
              child: const PatientTreatmentPlansBody(),
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

      final consultCta =
          find.byKey(const Key('pending_quote_plan-2_consult_cta'));
      await tester.ensureVisible(consultCta);
      await tester.tap(consultCta);
      await tester.pumpAndSettle();

      expect(pushedLocation, '/financial?id=quote-99');
    });

    testWidgets(
        'plan « En cours » sans prochaine séance — pas de rangée '
        '« Prochaine séance » (#5289)', (tester) async {
      final bloc = MockPatientTreatmentPlansBloc();
      when(() => bloc.state)
          .thenReturn(const PatientTreatmentPlansLoaded([_plan]));

      await tester.pumpApp(
        BlocProvider<PatientTreatmentPlansBloc>.value(
          value: bloc,
          child: const PatientTreatmentPlansBody(),
        ),
      );

      expect(find.textContaining('Prochaine séance'), findsNothing);
    });

    testWidgets(
        'plan « En cours » avec prochaine séance programmée — rangée '
        '« Prochaine séance » en pied de carte (#5289)', (tester) async {
      final bloc = MockPatientTreatmentPlansBloc();
      when(() => bloc.state).thenReturn(
          PatientTreatmentPlansLoaded([_planWithNextAppointment]));

      await tester.pumpApp(
        BlocProvider<PatientTreatmentPlansBloc>.value(
          value: bloc,
          child: const PatientTreatmentPlansBody(),
        ),
      );

      final card = find.byKey(const Key('treatment_plan_plan-1'));
      expect(card, findsOneWidget);
      expect(find.byIcon(Icons.event), findsOneWidget);

      final textSpan = tester
          .widget<Text>(find.byKey(
              const Key('treatment_plan_plan-1_next_appointment_label')))
          .textSpan as TextSpan;
      expect(textSpan.toPlainText(), 'Prochaine séance mardi 11 août, 14:30');
      final boldSpan = textSpan.children!.last as TextSpan;
      expect(boldSpan.style?.fontWeight, FontWeight.bold);

      expect(
        find.descendant(of: card, matching: find.text('Voir')),
        findsOneWidget,
      );
    });

    testWidgets(
        '« Voir » sur la rangée « Prochaine séance » navigue vers l\'écran '
        'du rendez-vous correspondant, sans déclencher le tap de la carte '
        '(#5289)', (tester) async {
      final bloc = MockPatientTreatmentPlansBloc();
      when(() => bloc.state).thenReturn(
          PatientTreatmentPlansLoaded([_planWithNextAppointment]));

      String? pushedLocation;
      final router = GoRouter(
        initialLocation: '/treatment-plans',
        routes: [
          GoRoute(
            path: '/treatment-plans',
            builder: (_, __) => BlocProvider<PatientTreatmentPlansBloc>.value(
              value: bloc,
              child: const PatientTreatmentPlansBody(),
            ),
          ),
          GoRoute(
            path: '/mes-rdv',
            builder: (_, state) {
              pushedLocation = state.uri.toString();
              return const Scaffold(body: Text('mes-rdv'));
            },
          ),
          GoRoute(
            path: '/treatment-plans/:id',
            builder: (_, state) {
              pushedLocation = state.uri.toString();
              return const Scaffold(body: Text('detail'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();

      final nextAppointmentCta = find
          .byKey(const Key('treatment_plan_plan-1_next_appointment_cta'));
      await tester.ensureVisible(nextAppointmentCta);
      await tester.tap(nextAppointmentCta);
      await tester.pumpAndSettle();

      expect(pushedLocation, '/mes-rdv?id=appt-42');
    });

    testWidgets(
        'tap sur la carte (hors rangée « Prochaine séance ») navigue '
        'toujours vers le détail du plan (#5289)', (tester) async {
      final bloc = MockPatientTreatmentPlansBloc();
      when(() => bloc.state).thenReturn(
          PatientTreatmentPlansLoaded([_planWithNextAppointment]));

      String? pushedLocation;
      final router = GoRouter(
        initialLocation: '/treatment-plans',
        routes: [
          GoRoute(
            path: '/treatment-plans',
            builder: (_, __) => BlocProvider<PatientTreatmentPlansBloc>.value(
              value: bloc,
              child: const PatientTreatmentPlansBody(),
            ),
          ),
          GoRoute(
            path: '/treatment-plans/:id',
            builder: (_, state) {
              pushedLocation = state.uri.toString();
              return const Scaffold(body: Text('detail'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Réhabilitation implantaire'));
      await tester.pumpAndSettle();

      expect(pushedLocation, '/treatment-plans/plan-1');
    });

    testWidgets('liste vide — état vide affiché, pas d\'encart d\'information',
        (tester) async {
      final bloc = MockPatientTreatmentPlansBloc();
      when(() => bloc.state).thenReturn(const PatientTreatmentPlansLoaded([]));

      await tester.pumpApp(
        BlocProvider<PatientTreatmentPlansBloc>.value(
          value: bloc,
          child: const PatientTreatmentPlansBody(),
        ),
      );

      expect(find.byKey(const Key('treatment_plans_empty')), findsOneWidget);
      expect(find.byKey(const Key('treatment_plans_info_notice')),
          findsNothing);
    });

    testWidgets(
        'chargement — squelette affiché, plus de spinner centré (#5293)',
        (tester) async {
      final bloc = MockPatientTreatmentPlansBloc();
      when(() => bloc.state).thenReturn(const PatientTreatmentPlansLoading());

      await tester.pumpApp(
        BlocProvider<PatientTreatmentPlansBloc>.value(
          value: bloc,
          child: const PatientTreatmentPlansBody(),
        ),
      );

      expect(find.byKey(const Key('treatment_plans_loading')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(NubiaSkeletonLoader), findsWidgets);
      expect(find.byKey(const Key('treatment_plans_info_notice')),
          findsNothing);
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
        'AppBar titrée avec le titre du plan plutôt qu\'un libellé figé '
        '(#5295)', (tester) async {
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
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Réhabilitation implantaire'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'bandeau héros « Où vous en êtes » — étape courante dérivée des '
        'phases (#5295)', (tester) async {
      final cubit = MockPatientTreatmentPlanDetailCubit();
      when(() => cubit.state).thenReturn(
          PatientTreatmentPlanDetailLoaded(_planWithCoverageStates));

      await tester.pumpApp(
        BlocProvider<PatientTreatmentPlanDetailCubit>.value(
          value: cubit,
          child: const PatientTreatmentPlanDetailBody(),
        ),
      );

      final hero = find.byKey(const Key('treatment_plan_hero'));
      expect(hero, findsOneWidget);
      expect(
        find.descendant(of: hero, matching: find.text('OÙ VOUS EN ÊTES')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: hero, matching: find.text('Étape 2 sur 3')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: hero,
          matching: find.text('Endodontie et reconstitution · en cours'),
        ),
        findsOneWidget,
      );
      // Le titre du plan reste porté par l'AppBar, pas répété dans le héros.
      expect(
        find.descendant(
          of: hero,
          matching: find.text('Réhabilitation implantaire'),
        ),
        findsNothing,
      );
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
      expect(find.byKey(const Key('phase_phase-2_quote_cta')), findsNothing);
    });

    testWidgets('phase avec devis en attente — bandeau warning + CTA (#5300)',
        (tester) async {
      final cubit = MockPatientTreatmentPlanDetailCubit();
      when(() => cubit.state)
          .thenReturn(PatientTreatmentPlanDetailLoaded(_planWithPendingQuote));

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
      expect(
          textSpan.toPlainText(),
          'Un devis vous a été envoyé le 9 août. Cette étape ne peut pas '
          'être programmée avant votre accord.');
      final firstSpan = textSpan.children!.first as TextSpan;
      expect(firstSpan.style?.fontWeight, FontWeight.bold);
    });

    testWidgets(
        'CTA « Consulter et signer le devis » navigue vers l\'écran du '
        'devis correspondant (#5300)', (tester) async {
      final cubit = MockPatientTreatmentPlanDetailCubit();
      when(() => cubit.state)
          .thenReturn(PatientTreatmentPlanDetailLoaded(_planWithPendingQuote));

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

    testWidgets(
        'phase en cours sans rendez-vous programmé — pas de CTA (#5299)',
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
          find.byKey(const Key('phase_phase-2_appointment_cta')), findsNothing);
    });

    testWidgets(
        'phase en cours avec rendez-vous programmé — CTA « Voir mon '
        'rendez-vous » (#5299)', (tester) async {
      final cubit = MockPatientTreatmentPlanDetailCubit();
      when(() => cubit.state).thenReturn(const PatientTreatmentPlanDetailLoaded(
          _planWithScheduledAppointment));

      await tester.pumpApp(
        BlocProvider<PatientTreatmentPlanDetailCubit>.value(
          value: cubit,
          child: const PatientTreatmentPlanDetailBody(),
        ),
      );

      // Pas de CTA sur la phase terminée.
      expect(
          find.byKey(const Key('phase_phase-1_appointment_cta')), findsNothing);

      expect(find.byKey(const Key('phase_phase-2_appointment_cta')),
          findsOneWidget);
      expect(find.byIcon(Icons.event), findsOneWidget);
      expect(find.text('Voir mon rendez-vous'), findsOneWidget);
    });

    testWidgets(
        'CTA « Voir mon rendez-vous » navigue vers l\'écran des '
        'rendez-vous (#5299)', (tester) async {
      final cubit = MockPatientTreatmentPlanDetailCubit();
      when(() => cubit.state).thenReturn(const PatientTreatmentPlanDetailLoaded(
          _planWithScheduledAppointment));

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
            path: '/mes-rdv',
            builder: (_, state) {
              pushedLocation = state.uri.toString();
              return const Scaffold(body: Text('mes-rdv'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
          find.byKey(const Key('phase_phase-2_appointment_cta')));
      await tester.tap(find.byKey(const Key('phase_phase-2_appointment_cta')));
      await tester.pumpAndSettle();

      expect(pushedLocation, '/mes-rdv?id=appt-42');
    });

    testWidgets(
        'bloc .amt — libellé de couverture et montant honnête par phase '
        '(#5298)', (tester) async {
      final cubit = MockPatientTreatmentPlanDetailCubit();
      when(() => cubit.state).thenReturn(
          PatientTreatmentPlanDetailLoaded(_planWithCoverageStates));

      await tester.pumpApp(
        BlocProvider<PatientTreatmentPlanDetailCubit>.value(
          value: cubit,
          child: const PatientTreatmentPlanDetailBody(),
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('phase_phase-1_amount_row')),
          matching: find.text('Réglé'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('phase_phase-1_amount_row')),
          matching: find.text('82,42 €'),
        ),
        findsOneWidget,
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('phase_phase-2_amount_row')),
          matching: find.text('Couvert par votre devis signé'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('phase_phase-2_amount_row')),
          matching: find.text('353,50 €'),
        ),
        findsOneWidget,
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('phase_phase-3_amount_row')),
          matching: find.text('Estimation'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('phase_phase-3_amount_row')),
          matching: find.text('1 200 €'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'ligne .dt — « Réalisée le » sur une phase terminée, « Séance '
        'aujourd\'hui à » sur une phase en cours (#5298)', (tester) async {
      final cubit = MockPatientTreatmentPlanDetailCubit();
      when(() => cubit.state).thenReturn(
          PatientTreatmentPlanDetailLoaded(_planWithCoverageStates));

      await tester.pumpApp(
        BlocProvider<PatientTreatmentPlanDetailCubit>.value(
          value: cubit,
          child: const PatientTreatmentPlanDetailBody(),
        ),
      );

      expect(find.text('Réalisée le 22 juillet'), findsOneWidget);
      expect(find.textContaining('Séance aujourd\'hui à'), findsOneWidget);
    });

    testWidgets(
        'texte .wh — phrase en langue patient sous le titre quand fournie '
        'par la donnée (#5297)', (tester) async {
      final cubit = MockPatientTreatmentPlanDetailCubit();
      when(() => cubit.state).thenReturn(
          PatientTreatmentPlanDetailLoaded(_planWithCoverageStates));

      await tester.pumpApp(
        BlocProvider<PatientTreatmentPlanDetailCubit>.value(
          value: cubit,
          child: const PatientTreatmentPlanDetailBody(),
        ),
      );

      expect(
        find.text('Détartrage complet et soin d\'une carie sur la dent 26.'),
        findsOneWidget,
      );
    });

    testWidgets('phase sans description — aucun texte .wh affiché (#5297)',
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

      expect(_planDetail.phases.every((p) => p.description == null), isTrue);
      expect(
        find.text('Détartrage complet et soin d\'une carie sur la dent 26.'),
        findsNothing,
      );
    });
  });
}
