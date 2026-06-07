// test/widget/nubia_avatar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_patient/presentation/widgets/nubia_avatar.dart';

void main() {
  group('NubiaAvatar', () {
    testWidgets('initiales — affiche le texte', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: NubiaAvatar(initials: 'MD')),
          ),
        ),
      );
      expect(find.text('MD'), findsOneWidget);
    });

    testWidgets('rayon personnalisé — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: NubiaAvatar(initials: 'AB', radius: 32)),
          ),
        ),
      );
      expect(find.byType(NubiaAvatar), findsOneWidget);
    });

    testWidgets('avec imageUrl — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: NubiaAvatar(
                initials: 'XY',
                imageUrl: 'https://example.com/avatar.jpg',
              ),
            ),
          ),
        ),
      );
      expect(find.byType(NubiaAvatar), findsOneWidget);
    });
  });
}
