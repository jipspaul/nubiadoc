//! Tests widget : ligne d'identité secondaire de la barre d'identité patient
//! (#4956) — âge, date de naissance, dernière visite, praticien. Chaque
//! segment doit être masqué si sa donnée est absente (jamais affiché vide).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/widgets/patient_identity_bar.dart';

void main() {
  Future<void> pump(WidgetTester tester, ClinicalSession session) {
    return tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => PatientIdentityBar(
              session: session,
              textTheme: Theme.of(context).textTheme,
              globalSearchFocusNode: FocusNode(),
              onCompletePressed: null,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
      'affiche âge, date de naissance, dernière visite et praticien (Dr) séparés par ·',
      (tester) async {
    final birthDate = DateTime(1992, 3, 12);
    final session = ClinicalSession(
      id: 's1',
      appointmentId: 'a1',
      status: 'in_progress',
      acts: const [],
      patientBirthDate: birthDate,
      lastVisitDate: DateTime(2026, 7, 22),
      practitionerName: 'A. Rousseau',
    );
    await pump(tester, session);

    final now = DateTime.now();
    var age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }

    expect(
      find.textContaining(
          '$age ans · né(e) le 12/03/1992 · Dernière visite 22/07 · Dr A. Rousseau'),
      findsOneWidget,
    );
  });

  testWidgets(
      '#6398 — n\'ajoute pas de préfixe Dr en double si practitionerName le contient déjà',
      (tester) async {
    const session = ClinicalSession(
      id: 's5',
      appointmentId: 'a5',
      status: 'in_progress',
      acts: [],
      practitionerName: 'Dr Hugo Marin',
    );
    await pump(tester, session);

    expect(find.textContaining('Dr Dr Hugo Marin'), findsNothing);
    expect(find.textContaining('Dr Hugo Marin'), findsOneWidget);
  });

  testWidgets('masque les segments dont la donnée est absente', (tester) async {
    const session = ClinicalSession(
      id: 's2',
      appointmentId: 'a2',
      status: 'in_progress',
      acts: [],
    );
    await pump(tester, session);

    expect(find.textContaining('Dernière visite'), findsNothing);
    expect(find.textContaining('Dr '), findsNothing);
    expect(find.textContaining('né(e) le'), findsNothing);
  });

  testWidgets(
      '#4957 — une pastille d\'alerte clinique par alerte, avant la pastille de statut',
      (tester) async {
    const session = ClinicalSession(
      id: 's3',
      appointmentId: 'a3',
      status: 'in_progress',
      acts: [],
      medicalAlerts: [
        MedicalAlert(kind: 'allergie', label: 'pénicilline'),
        MedicalAlert(kind: 'medico_legal', label: 'Anticoagulant (AVK)'),
      ],
    );
    await pump(tester, session);

    expect(find.text('Allergie pénicilline'), findsOneWidget);
    expect(find.text('Anticoagulant (AVK)'), findsOneWidget);
    expect(
        find.byKey(const Key('clinical_alert_pill_allergie_pénicilline')),
        findsOneWidget);
    expect(
        find.byKey(const Key(
            'clinical_alert_pill_medico_legal_Anticoagulant (AVK)')),
        findsOneWidget);

    // Les pastilles d'alerte précèdent la pastille de statut de séance sur
    // la même ligne (`.n1` de la maquette) : position horizontale inférieure.
    final alertPillX = tester
        .getTopLeft(find.byKey(
            const Key('clinical_alert_pill_allergie_pénicilline')))
        .dx;
    final statusPillX =
        tester.getTopLeft(find.text('Séance en cours')).dx;
    expect(alertPillX, lessThan(statusPillX));
  });

  testWidgets('aucune pastille d\'alerte si la liste est vide', (tester) async {
    const session = ClinicalSession(
      id: 's4',
      appointmentId: 'a4',
      status: 'in_progress',
      acts: [],
    );
    await pump(tester, session);

    expect(find.byWidgetPredicate((w) => w is StatusPill && w.variant == StatusPillVariant.error),
        findsNothing);
  });
}
