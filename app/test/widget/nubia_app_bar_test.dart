// test/widget/nubia_app_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_patient/presentation/widgets/nubia_app_bar.dart';

void main() {
  group('NubiaAppBar', () {
    testWidgets('affiche le titre', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            appBar: NubiaAppBar(title: 'Mon Profil'),
          ),
        ),
      );
      expect(find.text('Mon Profil'), findsOneWidget);
    });

    testWidgets('affiche les actions', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: NubiaAppBar(
              title: 'RDV',
              actions: [
                IconButton(
                  key: const Key('edit'),
                  icon: const Icon(Icons.edit),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('edit')), findsOneWidget);
    });

    testWidgets('se rend sans erreur sans actions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            appBar: NubiaAppBar(title: 'Documents'),
          ),
        ),
      );
      expect(find.byType(NubiaAppBar), findsOneWidget);
    });
  });
}
