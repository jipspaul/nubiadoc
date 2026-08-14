//! Tests widget : encart « Plan en cours » (colonne contexte gauche PC
//! ≥ 1280 px, #4938).

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/ccam_picker.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_bloc.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_page.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_state.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_event.dart';

class MockConsultationCliniqueBloc
    extends MockBloc<ConsultationCliniqueEvent, ConsultationCliniqueState>
    implements ConsultationCliniqueBloc {}

class MockGetActsUseCase extends Mock implements GetActsUseCase {}

class MockFavoriteActsUseCase extends Mock implements FavoriteActsUseCase {}

const _activePlan = ActivePlanSummary(
  id: 'plan-1',
  title: 'Réhabilitation secteur 2',
  currentPhase: 2,
  totalPhases: 3,
  totalCostCents: 163592,
);

const _sessionWithActivePlan = ClinicalSession(
  id: 's1',
  appointmentId: 'a1',
  status: 'in_progress',
  acts: [],
  patientId: 'patient-1',
  activePlan: _activePlan,
);

const _sessionWithoutActivePlan = ClinicalSession(
  id: 's2',
  appointmentId: 'a2',
  status: 'in_progress',
  acts: [],
);

void main() {
  late MockConsultationCliniqueBloc bloc;

  setUp(() {
    bloc = MockConsultationCliniqueBloc();
    GetIt.instance.registerFactory<GetActsUseCase>(() => MockGetActsUseCase());
    final favoriteActs = MockFavoriteActsUseCase();
    when(() => favoriteActs.list()).thenAnswer((_) async => []);
    GetIt.instance.registerFactory<FavoriteActsUseCase>(() => favoriteActs);
    addTearDown(GetIt.instance.reset);
  });

  Widget buildPage() => MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: BlocProvider<ConsultationCliniqueBloc>.value(
            value: bloc,
            child: const ConsultationCliniqueBody(consultationId: 's1'),
          ),
        ),
      );

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildPage());
    await tester.pump();
  }

  testWidgets(
      '≥ 1280 px + plan actif → encart « Plan en cours » visible en colonne gauche',
      (tester) async {
    when(() => bloc.state).thenReturn(
        const ConsultationCliniqueLoaded(session: _sessionWithActivePlan));

    await pumpAt(tester, const Size(1400, 2400));

    expect(find.byKey(const Key('consultation_context_column_layout')),
        findsOneWidget);
    expect(find.byKey(const Key('active_plan_box')), findsOneWidget);
    expect(find.text('Plan en cours'), findsOneWidget);
    expect(find.text('Réhabilitation secteur 2'), findsOneWidget);
    expect(find.text('Phase 2 sur 3 · 1 635,92 €'), findsOneWidget);
    expect(find.text('Ouvrir le plan'), findsOneWidget);
  });

  testWidgets('< 1280 px → pas d\'encart (repli 2 colonnes hors périmètre)',
      (tester) async {
    when(() => bloc.state).thenReturn(
        const ConsultationCliniqueLoaded(session: _sessionWithActivePlan));

    await pumpAt(tester, const Size(1100, 2400));

    expect(find.byKey(const Key('active_plan_box')), findsNothing);
  });

  testWidgets('patient sans plan actif → aucun encart, aucun plan inventé',
      (tester) async {
    when(() => bloc.state).thenReturn(
        const ConsultationCliniqueLoaded(session: _sessionWithoutActivePlan));

    await pumpAt(tester, const Size(1400, 2400));

    expect(find.byKey(const Key('consultation_context_column_layout')),
        findsNothing);
    expect(find.byKey(const Key('active_plan_box')), findsNothing);
    expect(find.text('Plan en cours'), findsNothing);
  });
}
