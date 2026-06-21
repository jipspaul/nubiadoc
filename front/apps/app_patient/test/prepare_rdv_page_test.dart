import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/features/mes_rdv/prepare_rdv_page.dart';

// ── Fake prefs service ───────────────────────────────────────────────────────

class _FakePrefsService implements PrepareRdvPrefsService {
  Set<String> checked = {};

  @override
  Future<Set<String>> loadChecked(String rdvId) async => Set.from(checked);

  @override
  Future<void> saveChecked(String rdvId, Set<String> ids) async {
    checked = Set.from(ids);
  }
}

// ── Helper ───────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) => MaterialApp(home: child);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('PrepareRdvPage — loaded state', () {
    testWidgets('affiche les 3 items et l\'adresse en titre', (tester) async {
      await tester.pumpWidget(_wrap(PrepareRdvPage(
        appointmentId: 'rdv-1',
        prefsService: _FakePrefsService(),
      )));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('item_carte_vitale')), findsOneWidget);
      expect(find.byKey(const Key('item_carte_mutuelle')), findsOneWidget);
      expect(find.byKey(const Key('item_ordonnance')), findsOneWidget);
      expect(find.text('12 rue de la Paix, 75001 Paris'), findsOneWidget);
    });
  });

  group('PrepareRdvPage — toggle persiste', () {
    testWidgets('tap sur un item le coche et persiste dans le service',
        (tester) async {
      final prefs = _FakePrefsService();
      await tester.pumpWidget(_wrap(PrepareRdvPage(
        appointmentId: 'rdv-1',
        prefsService: prefs,
      )));
      await tester.pumpAndSettle();

      // Avant tap : icône non cochée
      expect(
        find.descendant(
          of: find.byKey(const Key('item_carte_vitale')),
          matching: find.byIcon(Icons.check_box),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('item_carte_vitale')));
      await tester.pumpAndSettle();

      // Après tap : icône cochée
      expect(
        find.descendant(
          of: find.byKey(const Key('item_carte_vitale')),
          matching: find.byIcon(Icons.check_box),
        ),
        findsOneWidget,
      );

      // État persisté dans le service
      expect(prefs.checked, contains('carte_vitale'));
    });
  });
}
