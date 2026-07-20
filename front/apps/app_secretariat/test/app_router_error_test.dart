import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';

import 'package:app_secretariat/router/app_router.dart';

class MockTokenStorage extends Mock implements TokenStorage {}

void main() {
  // Régression #3894 : une route inconnue (deep-link périmé) affichait
  // l'écran d'erreur PAR DÉFAUT de go_router, exposant l'exception brute
  // « GoException: no routes for location: … » à l'utilisateur final.
  testWidgets(
    'route inconnue affiche un 404 soigné, pas la GoException brute',
    (tester) async {
      final notifier = RouterNotifier(MockTokenStorage())..markAuthenticated();
      final router = AppRouter.create(notifier);
      // Navigue vers la route inconnue AVANT le premier pump : sinon
      // initialLocation (splash) redirige d'abord vers home, dont la page
      // exige des dépendances GetIt hors de propos ici.
      router.go('/route-qui-nexiste-pas');

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('Page introuvable'), findsOneWidget);
      expect(find.textContaining('GoException'), findsNothing);
      expect(find.text('Retour à l\'accueil'), findsOneWidget);
    },
  );
}
