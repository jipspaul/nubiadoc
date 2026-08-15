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
}
