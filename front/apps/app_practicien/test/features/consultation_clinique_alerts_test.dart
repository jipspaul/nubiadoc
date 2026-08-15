//! Tests widget : encart « Alertes du dossier » (colonne contexte gauche PC
//! ≥ 1280 px, #4936).

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

const _sessionWithAlerts = ClinicalSession(
  id: 's1',
  appointmentId: 'a1',
  status: 'in_progress',
  acts: [],
  medicalAlerts: [
    MedicalAlert(kind: 'allergie', label: 'Pénicilline'),
    MedicalAlert(kind: 'medico_legal', label: 'Anticoagulant (AVK)'),
  ],
);

const _sessionWithoutAlerts = ClinicalSession(
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
      '≥ 1280 px + alertes → encart visible en tête de la colonne gauche',
      (tester) async {
    when(() => bloc.state)
        .thenReturn(const ConsultationCliniqueLoaded(session: _sessionWithAlerts));

    await pumpAt(tester, const Size(1400, 2400));

    expect(find.byKey(const Key('consultation_context_column_layout')),
        findsOneWidget);
    final alertsBox = find.byKey(const Key('patient_alerts_box'));
    expect(alertsBox, findsOneWidget);
    expect(find.text('Alertes du dossier'), findsOneWidget);
    // #4957 — « Allergie Pénicilline » est désormais aussi affiché en
    // pastille d'en-tête (`PatientIdentityBar`) : on scope à l'encart pour
    // ne pas compter les deux occurrences.
    expect(find.descendant(of: alertsBox, matching: find.text('Allergie Pénicilline')),
        findsOneWidget);
    expect(
        find.descendant(
            of: alertsBox, matching: find.text('Anticoagulant (AVK)')),
        findsOneWidget);
  });

  testWidgets('< 1280 px → pas d\'encart (repli 2 colonnes hors périmètre)',
      (tester) async {
    when(() => bloc.state)
        .thenReturn(const ConsultationCliniqueLoaded(session: _sessionWithAlerts));

    await pumpAt(tester, const Size(1100, 2400));

    expect(find.byKey(const Key('consultation_context_column_layout')),
        findsNothing);
    expect(find.byKey(const Key('patient_alerts_box')), findsNothing);
  });

  testWidgets('dossier sans alerte → aucun encart, aucune ligne fantôme',
      (tester) async {
    when(() => bloc.state).thenReturn(
        const ConsultationCliniqueLoaded(session: _sessionWithoutAlerts));

    await pumpAt(tester, const Size(1400, 2400));

    expect(find.byKey(const Key('consultation_context_column_layout')),
        findsNothing);
    expect(find.byKey(const Key('patient_alerts_box')), findsNothing);
    expect(find.text('Alertes du dossier'), findsNothing);
  });
}
