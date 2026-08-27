//! Tests widget : `TreatmentPlansPage` (#4051) — chargement, empty state,
//! création de plan, création de phase.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/ccam_picker.dart';
import 'package:app_practicien/features/treatment_plans/treatment_plans_page.dart';

class _MockListPlans extends Mock implements ListTreatmentPlansUseCase {}

class _MockCreatePlan extends Mock implements CreateTreatmentPlanUseCase {}

class _MockCreatePhase extends Mock implements CreateTreatmentPhaseUseCase {}

class _MockGetPatient extends Mock implements GetCabinetPatientUseCase {}

class _MockGetActs extends Mock implements GetActsUseCase {}

class _MockFavoriteActs extends Mock implements FavoriteActsUseCase {}

const _emptyPlans = <TreatmentPlan>[];

final _patient = CabinetPatient(
  id: 'pat-1',
  cabinetId: 'cab-1',
  firstName: 'Julie',
  lastName: 'Martin',
  birthDate: DateTime(1985, 3, 10),
  createdAt: DateTime(2020, 1, 1),
);

final _planWithPhases = TreatmentPlan(
  id: 'plan-1',
  title: 'Plan implant',
  status: 'draft',
  createdAt: DateTime(2026, 1, 1),
  phases: const [
    TreatmentPhase(
      id: 'phase-1',
      position: 1,
      title: 'Phase 1 · Chirurgie',
      status: 'requested',
    ),
  ],
);

final _planNoPhases = TreatmentPlan(
  id: 'plan-2',
  title: 'Plan couronne',
  status: 'draft',
  createdAt: DateTime(2026, 1, 2),
  phases: const [],
);

final _planWithActivePhase = TreatmentPlan(
  id: 'plan-3',
  title: 'Plan endodontie',
  status: 'in_progress',
  createdAt: DateTime(2026, 1, 3),
  phases: const [
    TreatmentPhase(
      id: 'phase-active',
      position: 1,
      title: 'Endodontie et reconstitution',
      status: 'in_progress',
    ),
  ],
);

void main() {
  late _MockListPlans listPlans;
  late _MockCreatePlan createPlan;
  late _MockCreatePhase createPhase;
  late _MockGetPatient getPatient;
  late _MockGetActs getActs;
  late _MockFavoriteActs favoriteActs;

  setUp(() {
    listPlans = _MockListPlans();
    createPlan = _MockCreatePlan();
    createPhase = _MockCreatePhase();
    getPatient = _MockGetPatient();
    getActs = _MockGetActs();
    favoriteActs = _MockFavoriteActs();
    GetIt.instance.registerFactory<ListTreatmentPlansUseCase>(() => listPlans);
    GetIt.instance
        .registerFactory<CreateTreatmentPlanUseCase>(() => createPlan);
    GetIt.instance
        .registerFactory<CreateTreatmentPhaseUseCase>(() => createPhase);
    GetIt.instance.registerFactory<GetCabinetPatientUseCase>(() => getPatient);
    GetIt.instance.registerFactory<GetActsUseCase>(() => getActs);
    GetIt.instance.registerFactory<FavoriteActsUseCase>(() => favoriteActs);
    when(() => getPatient('pat-1')).thenAnswer((_) async => Right(_patient));
    when(() => favoriteActs.list()).thenAnswer((_) async => const []);
    addTearDown(GetIt.instance.reset);
  });

  Widget buildPage() => MaterialApp(
        theme: NubiaTheme.light,
        home: const TreatmentPlansPage(patientId: 'pat-1'),
      );

  testWidgets('aucun plan → empty state affiché', (tester) async {
    when(() => listPlans('pat-1'))
        .thenAnswer((_) async => const Right(_emptyPlans));

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('treatment_plans_empty')), findsOneWidget);
  });

  testWidgets('plans avec phases → liste affichée, triée par position',
      (tester) async {
    when(() => listPlans('pat-1')).thenAnswer(
      (_) async => Right([_planWithPhases, _planNoPhases]),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('treatment_plan_plan-1')), findsOneWidget);
    expect(find.byKey(const Key('treatment_phase_phase-1')), findsOneWidget);
    expect(find.text('Phase 1 · Chirurgie'), findsOneWidget);
    expect(
      find.byKey(const Key('treatment_plan_no_phases_plan-2')),
      findsOneWidget,
    );
  });

  testWidgets(
      'phase active → affordance « Ajouter un acte à cette phase » ouvre le CCAM picker',
      (tester) async {
    when(() => listPlans('pat-1')).thenAnswer(
      (_) async => Right([_planWithActivePhase]),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('treatment_phase_add_act_phase-active')),
      findsOneWidget,
    );
    expect(find.text('Ajouter un acte à cette phase'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsWidgets);

    await tester.tap(
      find.byKey(const Key('treatment_phase_add_act_button_phase-active')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ccam_search_field')), findsOneWidget);
  });

  testWidgets('phase non active → pas d\'affordance « Ajouter un acte »',
      (tester) async {
    when(() => listPlans('pat-1')).thenAnswer(
      (_) async => Right([_planWithPhases]),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.text('Ajouter un acte à cette phase'), findsNothing);
  });

  testWidgets('création de plan → saisie titre puis CreateTreatmentPlanUseCase',
      (tester) async {
    when(() => listPlans('pat-1'))
        .thenAnswer((_) async => const Right(_emptyPlans));
    when(() => createPlan('pat-1', 'Plan blanchiment'))
        .thenAnswer((_) async => const Right('plan-new'));

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('treatment_plans_new_plan_fab')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('treatment_plan_title_field')),
      'Plan blanchiment',
    );
    await tester.tap(find.byKey(const Key('treatment_plan_create_submit')));
    await tester.pumpAndSettle();

    verify(() => createPlan('pat-1', 'Plan blanchiment')).called(1);
  });

  testWidgets(
      'ajout de phase → position suivante calculée puis CreateTreatmentPhaseUseCase',
      (tester) async {
    when(() => listPlans('pat-1')).thenAnswer(
      (_) async => Right([_planWithPhases]),
    );
    when(() => createPhase('plan-1', 'Phase 2 · Prothèse', 2))
        .thenAnswer((_) async => const Right('phase-new'));

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('treatment_plan_add_phase_plan-1')));
    await tester.pumpAndSettle();

    // #5022 : composition en place, plus d'AlertDialog pour la phase.
    expect(find.byType(AlertDialog), findsNothing);

    await tester.enterText(
      find.byKey(const Key('treatment_phase_title_field_plan-1')),
      'Phase 2 · Prothèse',
    );
    await tester
        .tap(find.byKey(const Key('treatment_phase_create_submit_plan-1')));
    await tester.pumpAndSettle();

    verify(() => createPhase('plan-1', 'Phase 2 · Prothèse', 2)).called(1);
  });

  testWidgets('erreur de chargement → NubiaErrorWidget avec bouton réessayer',
      (tester) async {
    when(() => listPlans('pat-1')).thenAnswer(
      (_) async => const Left(ServerFailure(message: 'Erreur serveur.')),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('treatment_plans_error')), findsOneWidget);
    expect(find.text('Erreur serveur.'), findsOneWidget);
  });

  testWidgets('bandeau patient → nom, âge et libellé « Plans de traitement »',
      (tester) async {
    when(() => listPlans('pat-1'))
        .thenAnswer((_) async => const Right(_emptyPlans));

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('treatment_plans_header')), findsOneWidget);
    expect(find.text('Julie Martin'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && RegExp(r'^\d+ ans$').hasMatch(w.data ?? ''),
      ),
      findsOneWidget,
    );
    expect(find.text('Plans de traitement'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('bandeau patient → bouton retour fait un pop de navigation',
      (tester) async {
    when(() => listPlans('pat-1'))
        .thenAnswer((_) async => const Right(_emptyPlans));

    await tester.pumpWidget(MaterialApp(
      theme: NubiaTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open_treatment_plans'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const TreatmentPlansPage(patientId: 'pat-1'),
                ),
              ),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('open_treatment_plans')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('treatment_plans_header')), findsOneWidget);

    await tester.tap(find.byKey(const Key('treatment_plans_back_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open_treatment_plans')), findsOneWidget);
    expect(find.byKey(const Key('treatment_plans_header')), findsNothing);
  });
}
