import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'support/harness.dart';

const _fields = <NubiaQuestionnaireFieldSpec>[
  NubiaQuestionnaireFieldSpec(
    key: 'allergies',
    type: NubiaQuestionnaireFieldType.text,
    label: 'Allergies',
  ),
  NubiaQuestionnaireFieldSpec(
    key: 'diabete',
    type: NubiaQuestionnaireFieldType.boolean,
    label: 'Diabète ?',
    highlighted: true,
  ),
  NubiaQuestionnaireFieldSpec(
    key: 'type',
    type: NubiaQuestionnaireFieldType.select,
    label: 'Régime',
    options: ['Végétarien', 'Sans gluten'],
    required: true,
  ),
];

void main() {
  group('NubiaDynamicQuestionnaireForm', () {
    testWidgets('rend un champ par type, préchargé depuis values',
        (tester) async {
      await tester.pumpWidget(
        wrap(
          NubiaDynamicQuestionnaireForm(
            fields: _fields,
            values: const {'allergies': 'Pénicilline', 'diabete': true},
            onChanged: (_, __) {},
          ),
        ),
      );

      expect(
        find.byKey(const Key('questionnaire_field_allergies')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('questionnaire_field_diabete')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('questionnaire_field_type')),
        findsOneWidget,
      );
      expect(find.text('Pénicilline'), findsOneWidget);
      final switchTile = tester.widget<SwitchListTile>(
        find.byKey(const Key('questionnaire_field_diabete')),
      );
      expect(switchTile.value, isTrue);
      // Champ requis : le libellé porte un astérisque.
      expect(find.text('Régime *'), findsOneWidget);
    });

    testWidgets('saisie texte remonte via onChanged(key, value)',
        (tester) async {
      final changes = <String, dynamic>{};
      await tester.pumpWidget(
        wrap(
          NubiaDynamicQuestionnaireForm(
            fields: _fields,
            values: const {},
            onChanged: (key, value) => changes[key] = value,
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('questionnaire_field_allergies')),
        'Latex',
      );

      expect(changes['allergies'], 'Latex');
    });

    testWidgets('bascule le switch remonte via onChanged(key, value)',
        (tester) async {
      final changes = <String, dynamic>{};
      await tester.pumpWidget(
        wrap(
          NubiaDynamicQuestionnaireForm(
            fields: _fields,
            values: const {'diabete': false},
            onChanged: (key, value) => changes[key] = value,
          ),
        ),
      );

      await tester
          .tap(find.byKey(const Key('questionnaire_field_diabete')));
      await tester.pumpAndSettle();

      expect(changes['diabete'], isTrue);
    });

    testWidgets('readOnly désactive tous les champs (pas d\'interaction)',
        (tester) async {
      await tester.pumpWidget(
        wrap(
          const NubiaDynamicQuestionnaireForm(
            fields: _fields,
            values: {'diabete': false},
            readOnly: true,
          ),
        ),
      );

      final switchTile = tester.widget<SwitchListTile>(
        find.byKey(const Key('questionnaire_field_diabete')),
      );
      expect(switchTile.onChanged, isNull);

      final textField = tester.widget<NubiaTextField>(
        find.byKey(const Key('questionnaire_field_allergies')),
      );
      expect(textField.enabled, isFalse);
    });
  });
}
