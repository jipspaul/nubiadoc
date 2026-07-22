import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/cr_template_picker.dart';

const _generic = CrTemplate(
  id: 'tmpl-1',
  title: 'CR standard',
  bodyTemplate: 'Compte rendu générique',
);
const _matching = CrTemplate(
  id: 'tmpl-2',
  ccamCode: 'HBLD001',
  title: 'CR détartrage',
  bodyTemplate: 'Détartrage réalisé sans complication',
);
const _other = CrTemplate(
  id: 'tmpl-3',
  ccamCode: 'HBGD036',
  title: 'CR autre acte',
  bodyTemplate: 'Autre acte',
);

Future<CrTemplate?> _open(
  WidgetTester tester, {
  required Future<List<CrTemplate>> Function() loadTemplates,
  String? firstActCcamCode,
}) async {
  CrTemplate? result;
  await tester.pumpWidget(MaterialApp(
    theme: NubiaTheme.light,
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await CrTemplatePicker.show(
              context,
              loadTemplates: loadTemplates,
              firstActCcamCode: firstActCcamCode,
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

void main() {
  group('CrTemplatePicker', () {
    testWidgets('aucun modèle → empty state', (tester) async {
      await _open(tester, loadTemplates: () async => []);

      expect(find.byKey(const Key('cr_template_empty')), findsOneWidget);
    });

    testWidgets('groupe "Pour cet acte" en tête quand ccam_code correspond',
        (tester) async {
      await _open(
        tester,
        loadTemplates: () async => [_other, _generic, _matching],
        firstActCcamCode: 'HBLD001',
      );

      expect(find.text('Pour cet acte'), findsOneWidget);
      expect(find.byKey(const Key('cr_template_tmpl-2')), findsOneWidget);
      expect(find.text('Modèles génériques'), findsOneWidget);
      expect(find.text('Autres modèles'), findsOneWidget);
    });

    testWidgets('sans acte sélectionné → pas de groupe "Pour cet acte"',
        (tester) async {
      await _open(
        tester,
        loadTemplates: () async => [_generic, _matching],
      );

      expect(find.text('Pour cet acte'), findsNothing);
      expect(find.text('Modèles génériques'), findsOneWidget);
    });

    testWidgets('tap sur un modèle le retourne au caller', (tester) async {
      late CrTemplate? picked;
      await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await CrTemplatePicker.show(
                  context,
                  loadTemplates: () async => [_generic],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cr_template_tmpl-1')));
      await tester.pumpAndSettle();

      expect(picked, _generic);
    });
  });
}
