import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/ordonnances/widgets/ordonnance_preview_sheet.dart';

final _patient = CabinetPatient(
  id: 'patient-1',
  cabinetId: 'cab-1',
  firstName: 'Julie',
  lastName: 'Martin',
  birthDate: DateTime(1985, 6, 7),
  createdAt: DateTime(2024, 1, 1),
);

const _paracetamol = PrescriptionItem(
  label: 'Paracétamol 1 g',
  form: 'comprimé',
  posology: '1 comprimé, 3 fois par jour',
  duration: '5 jours',
  quantity: '15 comprimés',
);

const _chlorhexidine = PrescriptionItem(
  label: 'Chlorhexidine 0,12 %',
  posology: '1 bain de bouche, 2 fois par jour',
  duration: '10 jours',
  quantity: '1 flacon 300 ml',
  substitutable: false,
);

Widget _wrap(Widget child) =>
    MaterialApp(theme: NubiaTheme.light, home: Scaffold(body: child));

void main() {
  group('OrdonnancePreviewSheet', () {
    testWidgets(
        'affiche prescripteur, patient et lignes Rx (titre, posologie, '
        'quantité) (#4997)', (tester) async {
      await tester.pumpWidget(_wrap(OrdonnancePreviewSheet(
        patient: _patient,
        prescriberName: 'Amélie Rousseau',
        items: const [_paracetamol],
      )));

      expect(find.text('Dr Amélie Rousseau'), findsOneWidget);
      expect(find.textContaining('Julie Martin'), findsOneWidget);
      expect(find.textContaining('né(e) le 07/06/1985'), findsOneWidget);
      expect(find.text('Paracétamol 1 g, comprimé'), findsOneWidget);
      expect(
        find.text('1 comprimé, 3 fois par jour, pendant 5 jours'),
        findsOneWidget,
      );
      expect(find.text('Quantité : 15 comprimés'), findsOneWidget);
    });

    testWidgets(
        'ligne non substituable → mention "Non substituable — MTE" en '
        'évidence (#4997)', (tester) async {
      await tester.pumpWidget(_wrap(const OrdonnancePreviewSheet(
        patient: null,
        prescriberName: null,
        items: [_chlorhexidine],
      )));

      expect(find.text('Non substituable — MTE'), findsOneWidget);
    });

    testWidgets('ligne substituable → aucune mention affichée (#4997)',
        (tester) async {
      await tester.pumpWidget(_wrap(const OrdonnancePreviewSheet(
        patient: null,
        prescriberName: null,
        items: [_paracetamol],
      )));

      expect(find.text('Non substituable — MTE'), findsNothing);
    });

    testWidgets(
        'aucune ligne saisie → message d\'invite plutôt qu\'une feuille vide',
        (tester) async {
      await tester.pumpWidget(_wrap(const OrdonnancePreviewSheet(
        patient: null,
        prescriberName: null,
        items: [],
      )));

      expect(find.text('Ajoutez un médicament pour voir l\'ordonnance.'),
          findsOneWidget);
      expect(find.text('0 médicament(s)'), findsOneWidget);
    });

    testWidgets(
        'prescripteur/patient absents → replis génériques sans crash '
        '(#4997)', (tester) async {
      await tester.pumpWidget(_wrap(const OrdonnancePreviewSheet(
        patient: null,
        prescriberName: null,
        items: [_paracetamol],
      )));

      expect(find.text('Praticien'), findsOneWidget);
      expect(find.text('Patient'), findsOneWidget);
    });

    testWidgets(
        'les props changent (frappe dans le formulaire) → l\'aperçu se met '
        'à jour (#4997)', (tester) async {
      await tester.pumpWidget(_wrap(const OrdonnancePreviewSheet(
        patient: null,
        prescriberName: null,
        items: [],
      )));
      expect(find.textContaining('Chlorhexidine'), findsNothing);

      await tester.pumpWidget(_wrap(const OrdonnancePreviewSheet(
        patient: null,
        prescriberName: null,
        items: [_chlorhexidine],
      )));

      expect(find.textContaining('Chlorhexidine'), findsOneWidget);
      expect(find.text('1 médicament(s)'), findsOneWidget);
    });
  });
}
