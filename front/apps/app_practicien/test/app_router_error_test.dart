import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';

import 'package:app_practicien/features/dashboard/opportunity_category_page.dart';
import 'package:app_practicien/router/app_router.dart';

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

  // Régression #8437 : `/opportunites` (#8407) attend sa catégorie via
  // `state.extra`, qui ne survit pas au bouton Suivant du navigateur ni à
  // un accès direct par URL — go_router construisait alors un
  // `Scaffold(body: SizedBox.shrink())`, un écran 100% blanc sans aucun
  // moyen de sortir. La route redirige maintenant vers le tableau de bord
  // quand `extra` n'est pas une `OpportunityCategory`.
  testWidgets(
    "/opportunites sans catégorie en `extra` redirige vers l'accueil, "
    "pas d'écran blanc",
    (tester) async {
      final notifier = RouterNotifier(MockTokenStorage())..markAuthenticated();
      final router = AppRouter.create(notifier);
      router.go(AppRouter.opportunityCategory);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();

      // La page d'accueil réelle exige des dépendances GetIt hors de
      // propos ici (DashboardBloc, etc.) — sa construction échoue donc
      // plus loin, mais ça prouve justement que le redirect a bien quitté
      // `/opportunites` : avant #8437, aucune exception n'était levée et
      // `OpportunityCategoryPage` restait l'écran courant (vide).
      expect(tester.takeException(), isNotNull);
      expect(find.byType(OpportunityCategoryPage), findsNothing);
      expect(
        router.routeInformationProvider.value.uri.toString(),
        AppRouter.home,
      );
    },
  );
}
