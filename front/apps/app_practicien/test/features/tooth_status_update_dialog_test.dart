//! Tests widget : dialogue de proposition de mise à jour d'odontogramme
//! (module dentaire, lot 3). « Ignorer » ne déclenche AUCUNE écriture —
//! garde-fou non-dispositif-médical.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_practicien/features/consultation_clinique/modules/dentaire/tooth_status_update_dialog.dart';

void main() {
  // Retourne le Future du dialogue encore ouvert (type doublement enveloppé
  // pour empêcher l'aplatissement async d'attendre sa fermeture).
  Future<Future<String?>> openDialog(WidgetTester tester) async {
    late Future<String?> result;
    await tester.pumpWidget(MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              result = ToothStatusUpdateDialog.show(
                context,
                tooth: '26',
                actLabel: 'Pose d\'implant intra-osseux',
                suggestedStatus: 'implant',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('affiche la dent, l\'acte et pré-sélectionne le statut proposé',
      (tester) async {
    await openDialog(tester);

    expect(find.byKey(const Key('tooth_status_update_dialog')), findsOneWidget);
    expect(find.text('Mettre à jour l\'état de la dent 26 ?'), findsOneWidget);
    expect(find.textContaining('Pose d\'implant'), findsOneWidget);
    final suggested = tester.widget<NubiaChip>(
        find.byKey(const Key('tooth_status_choice_implant')));
    expect(suggested.selected, isTrue);
  });

  testWidgets('« Ignorer » → résout null (aucune écriture)', (tester) async {
    final future = await openDialog(tester);

    await tester.tap(find.byKey(const Key('tooth_status_update_ignore')));
    await tester.pumpAndSettle();

    expect(await future, isNull);
    expect(find.byKey(const Key('tooth_status_update_dialog')), findsNothing);
  });

  testWidgets('« Mettre à jour » → résout le statut choisi', (tester) async {
    final future = await openDialog(tester);

    // Le praticien peut corriger la proposition avant de valider.
    await tester.tap(find.byKey(const Key('tooth_status_choice_couronne')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tooth_status_update_confirm')));
    await tester.pumpAndSettle();

    expect(await future, 'couronne');
  });
}
