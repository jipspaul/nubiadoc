import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

// Three destinations: two regular + one clinical-only.
const _destinations = [
  ProNavDestination(
    label: 'Agenda',
    icon: Icons.calendar_today,
    route: '/agenda',
  ),
  ProNavDestination(
    label: 'Patients',
    icon: Icons.people,
    route: '/patients',
  ),
  ProNavDestination(
    label: 'Journal clinique',
    icon: Icons.medical_services,
    route: '/journal',
    requiresClinical: true,
  ),
];

const _config = ProConfig(
  appTitle: 'Nubia Pro',
  spaceLabel: 'Cabinet Test',
  destinations: _destinations,
);

Widget _buildShell(AuthSession session) => MaterialApp(
      theme: NubiaTheme.light,
      home: ProShell(config: _config, session: session),
    );

// Default test surface is 800×600 — well above 720 px → desktop (NavigationRail).
void main() {
  group('ProShell — destinations', () {
    testWidgets('shows all destinations when canAccessClinical is true',
        (tester) async {
      const session = AuthSession(
        kind: UserKind.pro,
        userId: 'user-1',
        role: ProRole.practitioner,
      );
      await tester.pumpWidget(_buildShell(session));
      await tester.pumpAndSettle();

      expect(find.text('Agenda'), findsWidgets);
      expect(find.text('Patients'), findsWidgets);
      expect(find.text('Journal clinique'), findsWidgets);
    });

    testWidgets('hides clinical destination when not authorized',
        (tester) async {
      const session = AuthSession(
        kind: UserKind.pro,
        userId: 'user-2',
        role: ProRole.secretary, // canAccessClinical == false
      );
      await tester.pumpWidget(_buildShell(session));
      await tester.pumpAndSettle();

      expect(find.text('Agenda'), findsWidgets);
      expect(find.text('Patients'), findsWidgets);
      expect(find.text('Journal clinique'), findsNothing);
    });

    testWidgets('shows drawer on mobile layout (width < 720)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const session = AuthSession(
        kind: UserKind.pro,
        userId: 'user-3',
        role: ProRole.admin,
      );
      await tester.pumpWidget(_buildShell(session));
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.drawer, isNotNull);
    });
  });

  // --- Badges compteurs sur le rail (#5387) -----------------------------------
  group('ProShell — badges compteurs', () {
    const badgeDestinations = [
      ProNavDestination(
        label: 'Salle d\'attente',
        icon: Icons.meeting_room,
        route: '/salle-attente',
        badgeCount: 5,
      ),
      ProNavDestination(
        label: 'Agenda',
        icon: Icons.calendar_today,
        route: '/agenda',
      ),
      ProNavDestination(
        label: 'Devis',
        icon: Icons.description,
        route: '/devis',
        badgeCount: 0,
      ),
    ];

    const coloredBadgeDestinations = [
      ProNavDestination(
        label: 'Salle d\'attente',
        icon: Icons.meeting_room,
        route: '/salle-attente',
        badgeCount: 5,
      ),
      ProNavDestination(
        label: 'Demandes de créneau',
        icon: Icons.hourglass_top,
        route: '/liste-attente',
        badgeCount: 3,
        badgeColor: ProNavBadgeColor.warning,
      ),
    ];

    const coloredBadgeConfig = ProConfig(
      appTitle: 'Nubia Pro',
      spaceLabel: 'Cabinet Test',
      destinations: coloredBadgeDestinations,
    );

    const badgeConfig = ProConfig(
      appTitle: 'Nubia Pro',
      spaceLabel: 'Cabinet Test',
      destinations: badgeDestinations,
    );

    const session = AuthSession(
      kind: UserKind.pro,
      userId: 'user-4',
      role: ProRole.secretary,
    );

    testWidgets(
      'badgeCount > 0 : badge visible avec le compteur (rail desktop)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: ProShell(config: badgeConfig, session: session),
          ),
        );
        await tester.pumpAndSettle();

        final badges = tester.widgetList<Badge>(find.byType(Badge)).toList();
        final visible = badges.where((b) => b.isLabelVisible == true);
        expect(visible, hasLength(1));
        expect((visible.first.label as Text).data, '5');
      },
    );

    testWidgets(
      'badgeColor.brand → vert (--brand600), badgeColor.warning → ambre '
      '(--warnFg) (#5142)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: ProShell(config: coloredBadgeConfig, session: session),
          ),
        );
        await tester.pumpAndSettle();

        final badges = tester.widgetList<Badge>(find.byType(Badge)).toList();
        final byLabel = {
          for (final b in badges) (b.label as Text).data: b,
        };

        expect(byLabel['5']?.backgroundColor, NubiaColors.brand600);
        expect(byLabel['3']?.backgroundColor, NubiaTokens.light.warningFg);
      },
    );

    testWidgets(
      'badgeCount null ou 0 : aucun badge visible (pas de pastille vide)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: ProShell(config: badgeConfig, session: session),
          ),
        );
        await tester.pumpAndSettle();

        final badges = tester.widgetList<Badge>(find.byType(Badge)).toList();
        // 3 destinations → 3 Badge wrappers, 2 masqués (null et 0).
        expect(badges.length, 3);
        expect(badges.where((b) => b.isLabelVisible == false), hasLength(2));
      },
    );

    // #6555 — le compteur peint par le Badge (#5387) est écarté de l'arbre
    // Semantics par le `excludeSemantics: true` de `_sidebarEntry` (#6192) :
    // il doit donc être concaténé au label du nœud englobant, comme le fait
    // déjà `ProNotificationsBell` (« Notifications 46 »).
    testWidgets(
      'badgeCount > 0 : le compteur est exposé dans le label Semantics '
      '(rail desktop)',
      (tester) async {
        final handle = tester.ensureSemantics();

        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: ProShell(
              config: badgeConfig,
              session: session,
              currentRoute: '/agenda',
            ),
          ),
        );
        await tester.pumpAndSettle();

        final withBadge = tester.getSemantics(find.text('Salle d\'attente'));
        expect(withBadge.label, 'Salle d\'attente, 5');

        // badgeCount == 0 : pas de pastille visible, label inchangé (#5387).
        final withoutBadge = tester.getSemantics(find.text('Devis'));
        expect(withoutBadge.label, 'Devis');

        handle.dispose();
      },
    );

    testWidgets(
      'badgeCount > 0 : badge visible dans le drawer mobile',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: ProShell(config: badgeConfig, session: session),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();

        final badges = tester.widgetList<Badge>(find.byType(Badge)).toList();
        final visible = badges.where((b) => b.isLabelVisible == true);
        expect(visible, hasLength(1));
        expect((visible.first.label as Text).data, '5');
      },
    );
  });

  // --- Groupe repliable (#5139) -----------------------------------------
  group('ProShell — groupe repliable', () {
    const groupName = 'Réglages du cabinet';
    const groupedDestinations = [
      ProNavDestination(
        label: 'Agenda',
        icon: Icons.calendar_today,
        route: '/agenda',
      ),
      ProNavDestination(
        label: 'Statistiques',
        icon: Icons.bar_chart,
        route: '/cabinet-stats',
        group: groupName,
      ),
      ProNavDestination(
        label: 'Membres',
        icon: Icons.group_outlined,
        route: '/admin-membres',
        group: groupName,
      ),
    ];

    const groupedConfig = ProConfig(
      appTitle: 'Nubia Pro',
      spaceLabel: 'Cabinet Test',
      destinations: groupedDestinations,
      collapsedGroups: {groupName},
    );

    const session = AuthSession(
      kind: UserKind.pro,
      userId: 'user-5',
      role: ProRole.secretary,
    );

    testWidgets(
      'replié par défaut : les entrées du groupe sont masquées (drawer '
      'mobile)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: ProShell(config: groupedConfig, session: session),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();

        expect(find.text('Agenda'), findsWidgets);
        expect(find.text(groupName), findsOneWidget);
        expect(find.text('Statistiques'), findsNothing);
        expect(find.text('Membres'), findsNothing);
      },
    );

    testWidgets(
      "cliquer l'en-tête révèle les entrées, recliquer les masque (drawer "
      'mobile)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: ProShell(config: groupedConfig, session: session),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();

        await tester.tap(find.text(groupName));
        await tester.pumpAndSettle();
        expect(find.text('Statistiques'), findsOneWidget);
        expect(find.text('Membres'), findsOneWidget);

        await tester.tap(find.text(groupName));
        await tester.pumpAndSettle();
        expect(find.text('Statistiques'), findsNothing);
        expect(find.text('Membres'), findsNothing);
      },
    );

    testWidgets(
      "replié par défaut : les entrées du groupe sont masquées (rail "
      'desktop)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: ProShell(config: groupedConfig, session: session),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Agenda'), findsWidgets);
        expect(find.text(groupName), findsWidgets);
        expect(find.text('Statistiques'), findsNothing);
        expect(find.text('Membres'), findsNothing);
      },
    );

    testWidgets(
      "l'entrée active d'un groupe replié reste visible (rail desktop)",
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: ProShell(
              config: groupedConfig,
              session: session,
              currentRoute: '/cabinet-stats',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Statistiques'), findsWidgets);
      },
    );

    // #6192 — entrées et en-têtes de groupe absents de l'arbre Semantics
    // (uniquement quand des groupes sont déclarés, cf. app_secretariat).
    testWidgets(
      'entrées et en-tête de groupe exposent un bouton Semantics libellé '
      '(rail desktop)',
      (tester) async {
        final handle = tester.ensureSemantics();

        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: ProShell(
              config: groupedConfig,
              session: session,
              currentRoute: '/cabinet-stats',
            ),
          ),
        );
        await tester.pumpAndSettle();

        final agenda = tester.getSemantics(find.text('Agenda'));
        expect(agenda.flagsCollection.isButton, isTrue);
        expect(agenda.label, 'Agenda');

        final header = tester.getSemantics(find.text(groupName));
        expect(header.flagsCollection.isButton, isTrue);
        expect(header.label, groupName);

        handle.dispose();
      },
    );
  });
}
