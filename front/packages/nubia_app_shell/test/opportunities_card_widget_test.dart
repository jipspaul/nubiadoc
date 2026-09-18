import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

OpportunityCategory _category({
  required String kind,
  int count = 0,
  int totalAmountCents = 0,
  List<OpportunityItem>? items,
}) =>
    OpportunityCategory(
      kind: kind,
      count: count,
      totalAmountCents: totalAmountCents,
      items: items ?? const [],
    );

Widget _wrap(Widget child) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('affiche une ligne par catégorie avec libellé et compteur',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        OpportunitiesCard(
          categories: [
            _category(
              kind: 'quote_sent_no_response',
              count: 3,
              totalAmountCents: 125000,
            ),
            _category(kind: 'birthday_today', count: 0),
          ],
        ),
      ),
    );

    expect(find.text('Devis envoyés sans réponse'), findsOneWidget);
    expect(find.text('Anniversaires du jour'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('opportunity_row_quote_sent_no_response')),
        matching: find.text('1 250,00 €'),
      ),
      findsOneWidget,
    );
    // Badge total du header : 3 (opportunités) + 0 = 3.
    expect(
      find.descendant(
        of: find.byKey(const Key('opportunities_card_total')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'clic sur une ligne avec des opportunités appelle onCategoryTap',
    (tester) async {
      OpportunityCategory? tapped;
      final item = const OpportunityItem(
        kind: 'quote_sent_no_response',
        patientId: 'patient-1',
        quoteId: 'quote-1',
      );

      await tester.pumpWidget(
        _wrap(
          OpportunitiesCard(
            categories: [
              _category(
                kind: 'quote_sent_no_response',
                count: 1,
                items: [item],
              ),
            ],
            onCategoryTap: (context, category) => tapped = category,
          ),
        ),
      );

      await tester.tap(
        find.byKey(const Key('opportunity_row_quote_sent_no_response')),
      );
      await tester.pumpAndSettle();

      expect(tapped?.kind, 'quote_sent_no_response');
      expect(tapped?.items.single.quoteId, 'quote-1');
    },
  );

  testWidgets(
    'catégorie vide (count: 0) → ligne non cliquable',
    (tester) async {
      var tapCount = 0;

      await tester.pumpWidget(
        _wrap(
          OpportunitiesCard(
            categories: [_category(kind: 'birthday_today', count: 0)],
            onCategoryTap: (context, category) => tapCount++,
          ),
        ),
      );

      // Sans onTap (ListRow ne pose pas d'InkWell), le tap ne cible aucune
      // cible hit-testable — attendu, `warnIfMissed: false` pour ne pas
      // polluer la sortie de test.
      await tester.tap(
        find.byKey(const Key('opportunity_row_birthday_today')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(tapCount, 0);
    },
  );
}
