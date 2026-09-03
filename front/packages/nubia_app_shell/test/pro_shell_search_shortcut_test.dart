import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

const _destinations = [
  ProNavDestination(
      label: 'Agenda', icon: Icons.calendar_today, route: '/agenda'),
];

const _config = ProConfig(
  appTitle: 'Nubia Pro',
  spaceLabel: 'Cabinet Test',
  destinations: _destinations,
);

const _session =
    AuthSession(kind: UserKind.pro, userId: 'u1', role: ProRole.secretary);

/// `CallbackShortcuts` (pro_shell.dart) n'agit que si un descendant a le
/// focus (doc `CallbackShortcuts.bindings`) — un `Focus` autofocus reproduit
/// ce qu'un champ de saisie réel de la page routée obtiendrait.
Widget _focusableBody(BuildContext context, ProNavDestination destination) =>
    const Focus(autofocus: true, child: SizedBox.shrink());

void main() {
  // #6311 — les 3 apps pro sont des back-offices « PC » (maquettes
  // étiquetées DESKTOP/PC) : le raccourci de recherche globale doit
  // répondre à Ctrl+K sur Windows/Linux, pas seulement à ⌘K (macOS).
  testWidgets('⌘K ouvre la recherche globale', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: ProShell(
          config: _config,
          session: _session,
          searchHint: 'Patient, devis, commande…',
          onSearchTap: () => tapped = true,
          bodyBuilder: _focusableBody,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

    expect(tapped, isTrue);
  });

  testWidgets('Ctrl+K ouvre la recherche globale', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: ProShell(
          config: _config,
          session: _session,
          searchHint: 'Patient, devis, commande…',
          onSearchTap: () => tapped = true,
          bodyBuilder: _focusableBody,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(tapped, isTrue);
  });
}
