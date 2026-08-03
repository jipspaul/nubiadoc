//! Tests widget : bandeau patient de la vue fauteuil (refonte consultation,
//! lot 2 — maquette bo-praticien-core.jsx).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/widgets/patient_banner.dart';
import 'package:app_practicien/features/consultation_clinique/widgets/session_timer.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(body: child),
    );

ClinicalSession _session({
  PatientSummary? patient,
  String? patientName,
  DateTime? appointmentStartsAt,
  String? appointmentMotif,
  List<MedicalAlert> alerts = const [],
  CurrentPhase? phase,
  DateTime? startedAt,
  String status = 'in_progress',
}) =>
    ClinicalSession(
      id: 's1',
      appointmentId: 'a1',
      status: status,
      acts: const [],
      patient: patient,
      patientName: patientName,
      appointmentStartsAt: appointmentStartsAt,
      appointmentMotif: appointmentMotif,
      medicalAlerts: alerts,
      currentPhase: phase,
      startedAt: startedAt,
    );

const _phase = CurrentPhase(
  planId: 'p1',
  planTitle: 'Pose implant 26',
  phaseId: 'ph2',
  phaseTitle: 'Chirurgie implantaire',
  position: 2,
  phaseCount: 3,
  completedSessions: 1,
);

void main() {
  testWidgets('affiche nom, âge, heure de RDV, motif et phase', (tester) async {
    await tester.pumpWidget(_wrap(PatientBanner(
      session: _session(
        patient: const PatientSummary(
            id: 'pt1', displayName: 'Marc Dubois', ageYears: 48),
        appointmentStartsAt: DateTime(2026, 8, 3, 9, 0),
        appointmentMotif: 'Pose implant 26',
        phase: _phase,
      ),
    )));

    expect(find.text('Marc Dubois'), findsOneWidget);
    final meta =
        tester.widget<Text>(find.byKey(const Key('patient_banner_meta'))).data!;
    expect(meta, contains('48 ans'));
    expect(meta, contains('RDV 09:00'));
    expect(meta, contains('Pose implant 26 — phase 2/3'));
  });

  testWidgets('alertes médicales en badges passifs', (tester) async {
    await tester.pumpWidget(_wrap(PatientBanner(
      session: _session(
        patient: const PatientSummary(id: 'pt1', displayName: 'Marc Dubois'),
        alerts: const [
          MedicalAlert(kind: 'allergie', label: 'latex'),
          MedicalAlert(kind: 'medico_legal', label: 'Anticoagulants'),
        ],
      ),
    )));

    expect(find.text('Allergie latex'), findsOneWidget);
    expect(find.text('Anticoagulants'), findsOneWidget);
  });

  testWidgets('sans contexte enrichi : retombe sur patientName sans méta',
      (tester) async {
    await tester.pumpWidget(_wrap(PatientBanner(
      session: _session(patientName: 'Jeanne Petit'),
    )));

    expect(find.text('Jeanne Petit'), findsOneWidget);
    expect(find.byKey(const Key('patient_banner_meta')), findsNothing);
    expect(find.byType(NubiaBadge), findsNothing);
  });

  testWidgets('timer de séance affiché uniquement en cours', (tester) async {
    await tester.pumpWidget(_wrap(PatientBanner(
      session: _session(
        patientName: 'Marc Dubois',
        startedAt: DateTime.now().subtract(const Duration(minutes: 14)),
      ),
    )));
    // pump borné (pas de pumpAndSettle : le timer périodique ne « settle »
    // jamais).
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SessionTimer), findsOneWidget);
    expect(
      tester.widget<Text>(find.textContaining('Séance · ')).data,
      contains('14:'),
    );
  });

  testWidgets('pas de timer sur une séance terminée', (tester) async {
    await tester.pumpWidget(_wrap(PatientBanner(
      session: _session(
        patientName: 'Marc Dubois',
        status: 'completed',
        startedAt: DateTime.now().subtract(const Duration(minutes: 30)),
      ),
    )));
    expect(find.byType(SessionTimer), findsNothing);
  });
}
