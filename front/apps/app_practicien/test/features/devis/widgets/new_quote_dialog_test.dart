import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/devis/widgets/new_quote_dialog.dart';

class _ResultBox {
  List<QuoteLineItem>? value;
}

void main() {
  Future<_ResultBox> pumpAndOpen(WidgetTester tester) async {
    final box = _ResultBox();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              box.value = await showNewQuoteDialog(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return box;
  }

  testWidgets(
      '#8405 — ligne 2 avec montant invalide bloque la création au lieu '
      'd\'être avalée silencieusement', (tester) async {
    await pumpAndOpen(tester);

    await tester.tap(find.byKey(const Key('new_quote_add_line')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('new_quote_line_label_0')),
      'QA148 Ligne A valide',
    );
    await tester.enterText(
      find.byKey(const Key('new_quote_line_amount_0')),
      '100',
    );
    await tester.enterText(
      find.byKey(const Key('new_quote_line_label_1')),
      'QA148 Ligne B PERDUE',
    );
    await tester.enterText(
      find.byKey(const Key('new_quote_line_amount_1')),
      '90 euros',
    );

    await tester.tap(find.byKey(const Key('confirm_new_quote_button')));
    await tester.pumpAndSettle();

    // Le dialogue reste ouvert et pointe la ligne fautive plutôt que de
    // créer un devis à une seule ligne.
    expect(find.byKey(const Key('confirm_new_quote_button')), findsOneWidget);
    expect(find.text('Montant invalide ligne 2.'), findsOneWidget);
  });

  testWidgets(
      '#8433 — ligne 2 avec libellé vide mais montant renseigné bloque la '
      'création au lieu d\'être avalée silencieusement', (tester) async {
    await pumpAndOpen(tester);

    await tester.tap(find.byKey(const Key('new_quote_add_line')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('new_quote_line_label_0')),
      'QA149 Ligne A valide',
    );
    await tester.enterText(
      find.byKey(const Key('new_quote_line_amount_0')),
      '100',
    );
    await tester.enterText(
      find.byKey(const Key('new_quote_line_amount_1')),
      '50',
    );

    await tester.tap(find.byKey(const Key('confirm_new_quote_button')));
    await tester.pumpAndSettle();

    // Le dialogue reste ouvert et pointe la ligne fautive plutôt que de
    // créer un devis à une seule ligne (perte silencieuse des 50 €).
    expect(find.byKey(const Key('confirm_new_quote_button')), findsOneWidget);
    expect(find.text('Libellé manquant ligne 2.'), findsOneWidget);
  });

  testWidgets('ligne surnuméraire entièrement vide → ignorée sans erreur',
      (tester) async {
    final box = await pumpAndOpen(tester);

    await tester.tap(find.byKey(const Key('new_quote_add_line')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('new_quote_line_label_0')),
      'Acte test',
    );
    await tester.enterText(
      find.byKey(const Key('new_quote_line_amount_0')),
      '12,50',
    );

    await tester.tap(find.byKey(const Key('confirm_new_quote_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('confirm_new_quote_button')), findsNothing);
    expect(box.value, isNotNull);
    expect(box.value!.single.label, 'Acte test');
  });

  testWidgets('aucune ligne exploitable → message générique (#8388)',
      (tester) async {
    await pumpAndOpen(tester);

    await tester.tap(find.byKey(const Key('confirm_new_quote_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Ajoutez au moins une ligne avec un libellé et un montant.'),
      findsOneWidget,
    );
  });

  testWidgets('ligne valide unique → la création est acceptée',
      (tester) async {
    final box = await pumpAndOpen(tester);

    await tester.enterText(
      find.byKey(const Key('new_quote_line_label_0')),
      'Acte test',
    );
    await tester.enterText(
      find.byKey(const Key('new_quote_line_amount_0')),
      '12,50',
    );

    await tester.tap(find.byKey(const Key('confirm_new_quote_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('confirm_new_quote_button')), findsNothing);
    expect(box.value, isNotNull);
    expect(box.value!.single.label, 'Acte test');
    expect(box.value!.single.totalCents, 1250);
  });
}
