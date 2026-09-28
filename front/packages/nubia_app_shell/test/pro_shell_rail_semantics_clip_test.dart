import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

// Assez de destinations pour que le rail dépasse largement le viewport
// disponible à 1280×800 (#7859) — le cas réel (rail secrétariat) atteint 20
// lignes pour ~525px de hauteur utile ; on prend large pour couvrir aussi le
// `cacheExtent` par défaut (250px) au-delà du viewport.
final _destinations = [
  for (int i = 0; i < 40; i++)
    ProNavDestination(label: 'Dest $i', icon: Icons.circle, route: '/d$i'),
];

final _config = ProConfig(
  appTitle: 'Nubia Pro',
  spaceLabel: 'Cabinet Test',
  destinations: _destinations,
);

const _session =
    AuthSession(kind: UserKind.pro, userId: 'u1', role: ProRole.secretary);

void main() {
  testWidgets(
      'rail — les entrées hors du viewport ne publient pas de Semantics '
      'plein format à une position non cliquable (#7859)', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final handle = tester.ensureSemantics();

    await tester.pumpWidget(MaterialApp(
      theme: NubiaTheme.light,
      home: ProShell(config: _config, session: _session),
    ));
    await tester.pumpAndSettle();

    // Hauteur du rail effectivement disponible sous l'en-tête, avant le pied
    // de barre (bouton "Se déconnecter" etc.) : toute ligne dont le rect
    // Semantics dépasse cette limite serait annoncée comme active sans être
    // peinte/atteignable à cet endroit — exactement le bug #7859.
    final railBottom = tester
        .getTopLeft(find.byType(Scrollbar).last)
        .dy +
        tester.getSize(find.byType(Scrollbar).last).height;

    // ignore: deprecated_member_use
    final root = tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;

    void walk(SemanticsNode node, Matrix4 parentTransform) {
      final transform = parentTransform.clone();
      if (node.transform != null) transform.multiply(node.transform!);
      if (node.label.startsWith('Dest ')) {
        final global = MatrixUtils.transformRect(transform, node.rect);
        expect(
          global.top < railBottom,
          isTrue,
          reason: '"${node.label}" est annoncé à $global, entièrement sous '
              'la zone interactive du rail (bas ≈ $railBottom) — bouton mort.',
        );
      }
      node.visitChildren((child) {
        walk(child, transform);
        return true;
      });
    }

    walk(root, Matrix4.identity());
    handle.dispose();
  });
}
