import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

// Reproduit le rail secrétariat réel à 1280×800 : assez d'entrées en dehors
// du groupe repliable pour que la liste déjà dépliée remplisse tout juste le
// viewport (#6829), puis un groupe « Réglages du cabinet » dont les 2
// dernières destinations ne rentrent qu'après dépliage.
const _settingsGroup = 'Réglages du cabinet';

final _destinations = [
  for (int i = 0; i < 14; i++)
    ProNavDestination(label: 'Dest $i', icon: Icons.circle, route: '/d$i'),
  const ProNavDestination(
      label: 'Statistiques', icon: Icons.bar_chart, route: '/stats', group: _settingsGroup),
  const ProNavDestination(
      label: 'Créneaux ouverts', icon: Icons.event_available_outlined, route: '/slots', group: _settingsGroup),
  const ProNavDestination(
      label: 'Motifs de RDV', icon: Icons.event_note_outlined, route: '/motifs', group: _settingsGroup),
  const ProNavDestination(
      label: 'Stock', icon: Icons.inventory_2, route: '/stock', group: _settingsGroup),
];

final _config = ProConfig(
  appTitle: 'Nubia Pro',
  spaceLabel: 'Cabinet Test',
  destinations: _destinations,
  collapsedGroups: const {_settingsGroup},
);

const _session =
    AuthSession(kind: UserKind.pro, userId: 'u1', role: ProRole.secretary);

void main() {
  testWidgets(
      'rail — déplier un groupe fait défiler ses dernières destinations '
      'dans le viewport plutôt que de les laisser sous le bloc utilisateur '
      '(#6829)', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    ProNavDestination? navigated;

    await tester.pumpWidget(MaterialApp(
      theme: NubiaTheme.light,
      home: ProShell(
        config: _config,
        session: _session,
        onNavigate: (d) => navigated = d,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(_settingsGroup));
    await tester.pumpAndSettle();

    final railBottom = tester.getTopLeft(find.byType(Scrollbar).last).dy +
        tester.getSize(find.byType(Scrollbar).last).height;

    final stockRect = tester.getRect(find.text('Stock'));
    expect(
      stockRect.bottom <= railBottom,
      isTrue,
      reason: '"Stock" devrait être remonté dans le viewport scrollable '
          'après dépliage du groupe (rect $stockRect, bas du rail '
          '≈ $railBottom) au lieu de rester sous le bloc utilisateur.',
    );

    await tester.tap(find.text('Stock'));
    await tester.pumpAndSettle();
    expect(navigated?.route, '/stock');
  });
}
