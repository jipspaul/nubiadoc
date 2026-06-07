// test/widget/nubia_bottom_nav_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_patient/presentation/widgets/nubia_bottom_nav.dart';

void main() {
  group('NubiaBottomNav', () {
    testWidgets('affiche les 5 onglets sans erreur', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: NubiaBottomNav(
              currentIndex: 0,
              onTap: (_) {},
            ),
          ),
        ),
      );

      expect(find.byType(NubiaBottomNav), findsOneWidget);
      expect(find.text('Accueil'), findsOneWidget);
      expect(find.text('RDV'), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Documents'), findsOneWidget);
      expect(find.text('Profil'), findsOneWidget);
    });

    testWidgets('tap sur RDV (index 1) déclenche onTap(1)', (tester) async {
      int tapped = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: NubiaBottomNav(
              currentIndex: 0,
              onTap: (i) => tapped = i,
            ),
          ),
        ),
      );

      await tester.tap(find.text('RDV'));
      await tester.pump();

      expect(tapped, 1);
    });

    testWidgets('tap sur Messages (index 2) déclenche onTap(2)', (tester) async {
      int tapped = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: NubiaBottomNav(
              currentIndex: 0,
              onTap: (i) => tapped = i,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Messages'));
      await tester.pump();

      expect(tapped, 2);
    });

    testWidgets('tap sur Documents (index 3) déclenche onTap(3)',
        (tester) async {
      int tapped = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: NubiaBottomNav(
              currentIndex: 0,
              onTap: (i) => tapped = i,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Documents'));
      await tester.pump();

      expect(tapped, 3);
    });

    testWidgets('tap sur Profil (index 4) déclenche onTap(4)', (tester) async {
      int tapped = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: NubiaBottomNav(
              currentIndex: 0,
              onTap: (i) => tapped = i,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Profil'));
      await tester.pump();

      expect(tapped, 4);
    });

    testWidgets('affiche le badge quand unreadMessages > 0', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: NubiaBottomNav(
              currentIndex: 2,
              onTap: (_) {},
              unreadMessages: 3,
            ),
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('masque le badge quand unreadMessages == 0', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: NubiaBottomNav(
              currentIndex: 0,
              onTap: (_) {},
            ),
          ),
        ),
      );

      // Badge widget not present when count is 0
      expect(find.byType(Badge), findsNothing);
    });
  });
}
