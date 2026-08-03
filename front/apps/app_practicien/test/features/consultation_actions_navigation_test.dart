//! Tests widget : enchaînements cliniques depuis la séance (refonte lot 4) —
//! Prescrire une ordonnance pré-adressée (#4541), étape suivante du plan
//! (#4120), programmer le RDV.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/consultation_clinique_bloc.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_event.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_state.dart';
import 'package:app_practicien/features/consultation_clinique/widgets/next_step_panel.dart';
import 'package:app_practicien/features/consultation_clinique/widgets/session_actions_panel.dart';

class MockConsultationCliniqueBloc
    extends MockBloc<ConsultationCliniqueEvent, ConsultationCliniqueState>
    implements ConsultationCliniqueBloc {}

const _phase = CurrentPhase(
  planId: 'p1',
  planTitle: 'Pose implant 26',
  phaseId: 'ph2',
  phaseTitle: 'Chirurgie implantaire',
  position: 2,
  phaseCount: 3,
  completedSessions: 1,
);

const _sessionWithPatient = ClinicalSession(
  id: 's1',
  appointmentId: 'a1',
  status: 'in_progress',
  acts: [],
  patient: PatientSummary(id: 'pt1', displayName: 'Marc Dubois'),
  currentPhase: _phase,
);

const _sessionWithoutPatient = ClinicalSession(
  id: 's1',
  appointmentId: 'a1',
  status: 'in_progress',
  acts: [],
);

void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    required ClinicalSession session,
  }) async {
    final bloc = MockConsultationCliniqueBloc();
    whenListen(
      bloc,
      const Stream<ConsultationCliniqueState>.empty(),
      initialState: ConsultationCliniqueLoaded(session: session),
    );

    final router = GoRouter(
      initialLocation: '/panel',
      routes: [
        GoRoute(
          path: '/panel',
          builder: (_, __) => Scaffold(
            body: SingleChildScrollView(
              child: BlocProvider<ConsultationCliniqueBloc>.value(
                value: bloc,
                child: Column(
                  children: [
                    SessionActionsPanel(
                      session: session,
                      actionInProgress: false,
                    ),
                    if (session.currentPhase != null)
                      NextStepPanel(phase: session.currentPhase!),
                  ],
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/ordonnances/new',
          builder: (_, state) => Scaffold(
            body: Text(
                'ordonnance-new:${state.uri.queryParameters['patientId']}'),
          ),
        ),
        GoRoute(
          path: '/patients/:id/treatment-plans',
          builder: (_, state) => Scaffold(
            body: Text('treatment-plans:${state.pathParameters['id']}'),
          ),
        ),
        GoRoute(
          path: '/agenda',
          builder: (_, __) => const Scaffold(body: Text('agenda-page')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(
      theme: NubiaTheme.light,
      routerConfig: router,
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('« Prescrire une ordonnance » → /ordonnances/new pré-adressée',
      (tester) async {
    await pumpPanel(tester, session: _sessionWithPatient);

    await tester.ensureVisible(find.byKey(const Key('prescribe_button')));
    await tester.tap(find.byKey(const Key('prescribe_button')));
    await tester.pumpAndSettle();

    expect(find.text('ordonnance-new:pt1'), findsOneWidget);
  });

  testWidgets('« Étape suivante du plan » → plans de traitement du patient',
      (tester) async {
    await pumpPanel(tester, session: _sessionWithPatient);

    await tester.ensureVisible(find.byKey(const Key('next_plan_step_button')));
    await tester.tap(find.byKey(const Key('next_plan_step_button')));
    await tester.pumpAndSettle();

    expect(find.text('treatment-plans:pt1'), findsOneWidget);
  });

  testWidgets('« Programmer le RDV » (prochaine étape) → /agenda',
      (tester) async {
    await pumpPanel(tester, session: _sessionWithPatient);

    await tester
        .ensureVisible(find.byKey(const Key('next_step_schedule_button')));
    await tester.tap(find.byKey(const Key('next_step_schedule_button')));
    await tester.pumpAndSettle();

    expect(find.text('agenda-page'), findsOneWidget);
  });

  testWidgets('sans patient (payload minimal) : aucun bouton mort',
      (tester) async {
    await pumpPanel(tester, session: _sessionWithoutPatient);

    expect(find.byKey(const Key('prescribe_button')), findsNothing);
    expect(find.byKey(const Key('next_plan_step_button')), findsNothing);
  });
}
