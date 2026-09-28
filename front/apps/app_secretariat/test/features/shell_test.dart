import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  // --- Débordement du rail au déploiement de « Réglages du cabinet » (#6928) ---
  //
  // QA-20260913-17 : à 1280×800 (hauteur de référence secrétariat, cf.
  // `design/mockups/v2/INDEX.md`), déplier « Réglages du cabinet » (9
  // entrées) porte le rail à 21 lignes ; « Motifs de RDV » et « Stock »
  // sortaient du champ sans affordance et restaient annoncés dans l'arbre
  // Semantics à des coordonnées mortes (non peintes, non cliquables). Corrigé
  // entre-temps par #7706 (`Scrollbar` visible sur la colonne de rail) et
  // #7859 (`cacheExtent: 0`, qui évite justement qu'une ligne masquée publie
  // un Semantics plein format à une position inerte). Ce test rejoue le repro
  // exact sur la config réelle du secrétariat pour garantir la non-régression.
  group('ProShell — débordement du rail, groupe « Réglages du cabinet » (#6928)',
      () {
    const secretarySession = AuthSession(
      kind: UserKind.pro,
      userId: 'me',
      role: ProRole.secretary,
    );

    testWidgets(
      '1280×800 : une Scrollbar visible signale le débordement, et aucune '
      'entrée masquée n\'est annoncée à une position morte',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final handle = tester.ensureSemantics();

        await tester.pumpWidget(MaterialApp(
          theme: NubiaTheme.light,
          home: shell.ProShell(
            config: ProConfig.shellConfig,
            session: secretarySession,
          ),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Réglages du cabinet'));
        await tester.pumpAndSettle();

        // Affordance : la colonne signale visiblement qu'elle déborde.
        final scrollbarFinder = find.byType(Scrollbar);
        expect(scrollbarFinder, findsWidgets);
        final scrollbar = tester.widget<Scrollbar>(scrollbarFinder.last);
        expect(scrollbar.thumbVisibility, isTrue);

        final railBottom = tester.getTopLeft(scrollbarFinder.last).dy +
            tester.getSize(scrollbarFinder.last).height;

        // ignore: deprecated_member_use
        final root = tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;

        const settingsGroupLabels = [
          'Statistiques',
          'Créneaux ouverts',
          'Motifs de RDV',
          'Stock',
          'Maintenance',
          'Membres',
          'Secrétariats',
          "Journal d'audit",
          'Reprise de données',
        ];

        void walk(SemanticsNode node, Matrix4 parentTransform) {
          final transform = parentTransform.clone();
          if (node.transform != null) transform.multiply(node.transform!);
          if (settingsGroupLabels.contains(node.label)) {
            final global = MatrixUtils.transformRect(transform, node.rect);
            expect(
              global.top < railBottom,
              isTrue,
              reason: '"${node.label}" est annoncé à $global, entièrement '
                  'sous la zone interactive du rail (bas ≈ $railBottom) — '
                  'bouton mort.',
            );
          }
          node.visitChildren((child) {
            walk(child, transform);
            return true;
          });
        }

        walk(root, Matrix4.identity());
        handle.dispose();

        // Une fois amenée dans le viewport par un défilement explicite,
        // « Stock » reste bien atteignable.
        await tester.ensureVisible(find.text('Stock'));
        await tester.pumpAndSettle();
        expect(find.text('Stock'), findsOneWidget);
        await tester.tap(find.text('Stock'));
        await tester.pumpAndSettle();
      },
    );
  });
}
