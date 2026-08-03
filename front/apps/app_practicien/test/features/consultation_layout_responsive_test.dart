//! Tests widget : layout responsive de la vue « séance ouverte » (refonte
//! consultation, lot 2 — desktop 3 colonnes / tablette 2 colonnes / mobile
//! pile verticale, seuils de design/07-handoff/00-fondations.md).

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/ccam_picker.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_bloc.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_event.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_state.dart';
import 'package:app_practicien/features/consultation_clinique/widgets/consultation_loaded_view.dart';

class MockConsultationCliniqueBloc
    extends MockBloc<ConsultationCliniqueEvent, ConsultationCliniqueState>
    implements ConsultationCliniqueBloc {}

class MockGetActsUseCase extends Mock implements GetActsUseCase {}

class MockFavoriteActsUseCase extends Mock implements FavoriteActsUseCase {}

class MockGetDentalChartUseCase extends Mock implements GetDentalChartUseCase {}

class MockPutDentalChartUseCase extends Mock implements PutDentalChartUseCase {}

// startedAt volontairement absent : le SessionTimer périodique empêcherait
// pumpAndSettle de converger.
const _session = ClinicalSession(
  id: 's1',
  appointmentId: 'a1',
  status: 'in_progress',
  acts: [
    ClinicalAct(
        id: 'act-1',
        ccamCode: 'HBLD036',
        label: 'Pose implant',
        tooth: '26',
        amountCents: 95000),
  ],
  patient: PatientSummary(id: 'pt1', displayName: 'Marc Dubois', ageYears: 48),
  medicalHistory: 'Bruxisme nocturne',
  currentPhase: CurrentPhase(
    planId: 'p1',
    planTitle: 'Pose implant 26',
    phaseId: 'ph2',
    phaseTitle: 'Chirurgie implantaire',
    position: 2,
    phaseCount: 3,
    completedSessions: 1,
  ),
);

void main() {
  late MockConsultationCliniqueBloc bloc;

  setUp(() {
    bloc = MockConsultationCliniqueBloc();
    GetIt.instance.registerFactory<GetActsUseCase>(() => MockGetActsUseCase());
    final favoriteActs = MockFavoriteActsUseCase();
    when(() => favoriteActs.list()).thenAnswer((_) async => []);
    GetIt.instance.registerFactory<FavoriteActsUseCase>(() => favoriteActs);
    // La session de test a un patient → la vue crée le DentalChartCubit du
    // module dentaire (odontogramme intégré).
    final getChart = MockGetDentalChartUseCase();
    when(() => getChart.call(any())).thenAnswer(
      (_) async => Right(DentalChart(
        teeth: const {'26': ToothState(status: 'carie')},
        updatedAt: DateTime(2026, 8, 3),
      )),
    );
    GetIt.instance.registerFactory<GetDentalChartUseCase>(() => getChart);
    GetIt.instance
        .registerFactory<PutDentalChartUseCase>(MockPutDentalChartUseCase.new);
    addTearDown(GetIt.instance.reset);
  });

  Future<void> pumpAt(WidgetTester tester, Size logicalSize) async {
    tester.view.physicalSize = logicalSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    whenListen(
      bloc,
      const Stream<ConsultationCliniqueState>.empty(),
      initialState: const ConsultationCliniqueLoaded(session: _session),
    );

    await tester.pumpWidget(MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(
        body: BlocProvider<ConsultationCliniqueBloc>.value(
          value: bloc,
          child: const ConsultationLoadedView(
            state: ConsultationCliniqueLoaded(session: _session),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('desktop ≥1024 : bandeau + 3 colonnes (contexte, actes, actions)',
      (tester) async {
    await pumpAt(tester, const Size(1280, 900));

    expect(
        find.byKey(const Key('consultation_desktop_layout')), findsOneWidget);
    expect(find.byKey(const Key('patient_banner')), findsOneWidget);
    expect(find.byKey(const Key('clinical_context_panel')), findsOneWidget);
    expect(find.byKey(const Key('session_acts_panel')), findsOneWidget);
    expect(find.byKey(const Key('session_actions_panel')), findsOneWidget);
    expect(find.byKey(const Key('next_step_panel')), findsOneWidget);
    // Module dentaire : odontogramme intégré en colonne centrale.
    expect(find.byKey(const Key('odontogram_panel')), findsOneWidget);
    expect(find.text('Terminer & facturer'), findsOneWidget);
  });

  testWidgets('tablette 768-1023 : 2 colonnes, contexte inline',
      (tester) async {
    await pumpAt(tester, const Size(900, 800));

    expect(find.byKey(const Key('consultation_tablet_layout')), findsOneWidget);
    expect(find.byKey(const Key('session_actions_panel')), findsOneWidget);
    // Le contexte clinique reste accessible, dans la colonne centrale.
    expect(find.byKey(const Key('clinical_context_panel')), findsOneWidget);
  });

  testWidgets('mobile <768 : pile verticale, Terminer dans le bandeau',
      (tester) async {
    await pumpAt(tester, const Size(500, 800));

    expect(find.byKey(const Key('consultation_mobile_layout')), findsOneWidget);
    expect(find.byKey(const Key('patient_banner')), findsOneWidget);
    expect(find.byKey(const Key('session_actions_panel')), findsNothing);
    // Mobile : pas d'odontogramme inline, le bottom-sheet reste la voie.
    expect(find.byKey(const Key('odontogram_panel')), findsNothing);
    expect(
        find.byKey(const Key('complete_consultation_button')), findsOneWidget);
    expect(find.byKey(const Key('act_tooth_picker_button')), findsOneWidget);
  });

  testWidgets('desktop : « Terminer & facturer » envoie CompleteRequested',
      (tester) async {
    await pumpAt(tester, const Size(1280, 900));

    await tester.tap(find.byKey(const Key('complete_consultation_button')));
    verify(() => bloc.add(const ConsultationCliniqueCompleteRequested()))
        .called(1);
  });
}
