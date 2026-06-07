import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_demo/screens/vault/vault_screen.dart';
import 'package:flutter_demo/screens/vault/widgets/vault_document_card.dart';
import 'package:flutter_demo/theme/nubia_theme.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: NubiaTheme.light,
      home: child,
    );

void main() {
  group('VaultScreen', () {
    testWidgets('renders without throwing', (tester) async {
      await tester.pumpWidget(_wrap(const VaultScreen()));
      expect(find.byType(VaultScreen), findsOneWidget);
    });

    testWidgets('affiche les 8 documents mock par défaut', (tester) async {
      // Agrandir la fenêtre pour que tous les items soient rendus par le ListView.
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const VaultScreen()));
      expect(find.byType(VaultDocumentCard), findsNWidgets(8));
    });

    testWidgets('filtre par catégorie réduit la liste à 1 document',
        (tester) async {
      await tester.pumpWidget(_wrap(const VaultScreen()));

      // Tap sur le chip FilterChip « Devis » (pas le badge dans la carte)
      await tester.tap(find.widgetWithText(FilterChip, 'Devis'));
      await tester.pump();

      expect(find.byType(VaultDocumentCard), findsOneWidget);
      expect(find.text('Devis implant mandibulaire'), findsOneWidget);
    });

    testWidgets('filtre « Tous » réaffiche les 8 documents', (tester) async {
      // Agrandir la fenêtre pour que tous les items soient rendus par le ListView.
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const VaultScreen()));

      // Filtrer d'abord
      await tester.tap(find.widgetWithText(FilterChip, 'Devis'));
      await tester.pump();
      expect(find.byType(VaultDocumentCard), findsOneWidget);

      // Retour à Tous
      await tester.tap(find.widgetWithText(FilterChip, 'Tous'));
      await tester.pump();
      expect(find.byType(VaultDocumentCard), findsNWidgets(8));
    });

    testWidgets('tap Télécharger affiche SnackBar « Téléchargement simulé »',
        (tester) async {
      await tester.pumpWidget(_wrap(const VaultScreen()));

      // Trouver le premier bouton de téléchargement (doc v-001)
      await tester.tap(find.byKey(const Key('download_v-001')));
      await tester.pump();

      expect(find.text('Téléchargement simulé'), findsOneWidget);
    });
  });
}
