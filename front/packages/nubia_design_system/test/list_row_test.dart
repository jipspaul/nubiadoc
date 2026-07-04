import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(body: child),
    );

void main() {
  group('ListRow', () {
    testWidgets('affiche titre, sous-titre, leading et trailing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ListRow(
            title: 'Cabinet Lefèvre',
            subtitle: 'Votre ordonnance est disponible.',
            leading: NubiaAvatar(initials: 'CL'),
            trailing: Icon(Icons.chevron_right),
          ),
        ),
      );

      expect(find.text('Cabinet Lefèvre'), findsOneWidget);
      expect(find.text('Votre ordonnance est disponible.'), findsOneWidget);
      expect(find.byType(NubiaAvatar), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('variante non-lu : point coloré + titre en gras', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ListRow(
            title: 'Message non lu',
            subtitle: 'Extrait',
            unread: true,
          ),
        ),
      );

      // Le point non-lu est un Container circulaire (BoxShape.circle).
      final dot = tester.widgetList<Container>(find.byType(Container)).where(
            (c) =>
                c.decoration is BoxDecoration &&
                (c.decoration as BoxDecoration).shape == BoxShape.circle,
          );
      expect(dot, isNotEmpty);

      final titleText = tester.widget<Text>(find.text('Message non lu'));
      expect(titleText.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('déclenche onTap', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _wrap(ListRow(title: 'Ligne cliquable', onTap: () => tapped++)),
      );

      await tester.tap(find.text('Ligne cliquable'));
      await tester.pumpAndSettle();
      expect(tapped, 1);
    });
  });
}
