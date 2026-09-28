import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' as shell;
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_secretariat/pro_config.dart';

void main() {
  // --- Invariants statiques ProConfig ------------------------------------------
  group('ProConfig — shell secrétariat (includeClinical: false)', () {
    test('includeClinical est false', () {
      expect(ProConfig.includeClinical, isFalse);
    });

    test('aucune destination ne requiert un accès clinique', () {
      final clinicalDests = ProConfig.shellConfig.destinations
          .where((d) => d.requiresClinical)
          .toList();
      expect(clinicalDests, isEmpty);
    });
  });

  // --- Badges compteurs — couleurs sémantiques (#5142) --------------------------
  group('ProConfig.shellConfigFor — couleurs des badges', () {
    late Map<String, shell.ProNavDestination> destinationsByRoute;

    setUp(() {
      final config = ProConfig.shellConfigFor(
        canManageMembers: true,
        canViewAuditLog: true,
        waitingRoomCount: 5,
        waitingListCount: 3,
        expiringQuotesCount: 2,
        unreadMessagesCount: 4,
      );
      destinationsByRoute = {
        for (final d in config.destinations) d.route: d,
      };
    });

    test('Salle d\'attente : badge vert (personnes présentes)', () {
      expect(
        destinationsByRoute['/salle-attente']?.badgeColor,
        shell.ProNavBadgeColor.brand,
      );
    });

    test('Demandes de créneau : badge ambre', () {
      expect(
        destinationsByRoute['/liste-attente']?.badgeColor,
        shell.ProNavBadgeColor.warning,
      );
    });

    test('Devis : badge ambre (en attente de signature)', () {
      expect(
        destinationsByRoute['/devis']?.badgeColor,
        shell.ProNavBadgeColor.warning,
      );
    });

    test('Messages › Patients : badge vert (non lus)', () {
      expect(
        destinationsByRoute['/messages']?.badgeColor,
        shell.ProNavBadgeColor.brand,
      );
    });
  });

  // --- Widget tests : ProShell avec config secrétariat -------------------------
  group('ProShell — garde clinique secrétariat', () {
    const secretarySession = AuthSession(
      kind: UserKind.pro,
      userId: 'me',
      role: ProRole.secretary,
    );

    Widget buildShell() => MaterialApp(
          theme: NubiaTheme.light,
          home: shell.ProShell(
            config: ProConfig.shellConfig,
            session: secretarySession,
          ),
        );

    testWidgets(
      'affiche les destinations secrétariat configurées',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 900));
        addTearDown(tester.binding.reset);
        await tester.pumpWidget(buildShell());
        await tester.pumpAndSettle();

        expect(find.text('Salle d\'attente'), findsWidgets);
        expect(find.text('Patients'), findsWidgets);
      },
    );

    testWidgets(
      'aucune surface clinique affichée (includeClinical: false)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 900));
        addTearDown(tester.binding.reset);
        await tester.pumpWidget(buildShell());
        await tester.pumpAndSettle();

        expect(find.text('Consultation'), findsNothing);
        expect(find.text('Journal clinique'), findsNothing);
      },
    );

    testWidgets(
      'ProShell ne contient aucune destination requiresClinical',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 900));
        addTearDown(tester.binding.reset);
        await tester.pumpWidget(buildShell());
        await tester.pumpAndSettle();

        final shellWidget = tester.widget<shell.ProShell>(
          find.byType(shell.ProShell),
        );
        expect(
          shellWidget.config.destinations.any((d) => d.requiresClinical),
          isFalse,
        );
      },
    );
  });

  // --- Repli de l'en-tête du groupe de l'écran courant (#6944) -----------------
  //
  // QA-20260913-33 : sur les 4 groupes testés (« Ma journée », « Facturation »,
  // « Patients », « Messages »), un clic sur l'en-tête du groupe QUI CONTIENT
  // l'écran affiché était rapporté comme un bouton mort (aucun repli). Cette
  // régression a été corrigée entre-temps par #7029 (`_effectiveCollapsedGroups`
  // retiré) : l'en-tête reflète toujours l'état réel de `collapsedGroups`, et
  // seule la destination active reste visible dans son groupe replié. Ces tests
  // rejouent le repro exact de #6944 sur la config réelle du secrétariat pour
  // garantir la non-régression.
  group('ProShell — repli de l\'en-tête du groupe courant (#6944)', () {
    const secretarySession = AuthSession(
      kind: UserKind.pro,
      userId: 'me',
      role: ProRole.secretary,
    );

    Widget buildShell(String currentRoute) => MaterialApp(
          theme: NubiaTheme.light,
          home: shell.ProShell(
            config: ProConfig.shellConfig,
            session: secretarySession,
            currentRoute: currentRoute,
          ),
        );

    testWidgets(
      '/agenda : cliquer « Ma journée » replie les autres entrées du groupe',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 900));
        addTearDown(tester.binding.reset);
        await tester.pumpWidget(buildShell('/agenda'));
        await tester.pumpAndSettle();

        expect(find.text('Agenda'), findsWidgets);
        expect(find.text('Salle d\'attente'), findsOneWidget);

        await tester.tap(find.text('Ma journée'));
        await tester.pumpAndSettle();

        expect(find.text('Agenda'), findsWidgets);
        expect(find.text('Salle d\'attente'), findsNothing);
        expect(find.text('Demandes de créneau'), findsNothing);
      },
    );

    testWidgets(
      '/cabinet-payouts : cliquer « Facturation » replie « Devis »',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 900));
        addTearDown(tester.binding.reset);
        await tester.pumpWidget(buildShell('/cabinet-payouts'));
        await tester.pumpAndSettle();

        expect(find.text('Encaissements'), findsWidgets);
        expect(find.text('Devis'), findsOneWidget);

        await tester.tap(find.text('Facturation'));
        await tester.pumpAndSettle();

        expect(find.text('Encaissements'), findsWidgets);
        expect(find.text('Devis'), findsNothing);
      },
    );

    testWidgets(
      '/patients : cliquer « Patients » replie « Prendre un RDV »',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 900));
        addTearDown(tester.binding.reset);
        await tester.pumpWidget(buildShell('/patients'));
        await tester.pumpAndSettle();

        // #7710 — le libellé du groupe (« Patients ») coïncide avec celui de
        // la destination messagerie (`/messages`, groupe « Messages ») : on
        // vise l'en-tête par sa clé stable (#7692) plutôt que par son texte.
        expect(find.text('Fiches patients'), findsWidgets);
        expect(find.text('Prendre un RDV'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('group:Patients')));
        await tester.pumpAndSettle();

        expect(find.text('Fiches patients'), findsWidgets);
        expect(find.text('Prendre un RDV'), findsNothing);
        expect(find.text('Correspondants'), findsNothing);
      },
    );

    testWidgets(
      '/team-messages : cliquer « Messages » replie l\'entrée « Patients »',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 900));
        addTearDown(tester.binding.reset);
        await tester.pumpWidget(buildShell('/team-messages'));
        await tester.pumpAndSettle();

        // #7710 — même collision de libellé que ci-dessus, dans l'autre sens :
        // on vise la destination `/messages` (« Patients ») par sa clé.
        expect(find.text('Équipe'), findsWidgets);
        expect(find.byKey(const ValueKey('dest:/messages')), findsOneWidget);

        await tester.tap(find.text('Messages'));
        await tester.pumpAndSettle();

        expect(find.text('Équipe'), findsWidgets);
        expect(find.byKey(const ValueKey('dest:/messages')), findsNothing);
      },
    );
  });
}
