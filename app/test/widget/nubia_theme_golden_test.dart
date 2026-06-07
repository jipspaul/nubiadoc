// test/widget/nubia_theme_golden_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_patient/presentation/theme/nubia_colors.dart';
import 'package:nubia_patient/presentation/theme/nubia_tokens.dart';

/// Snapshot golden du thème Nubia — light mode (palette + tokens).
///
/// Valide les couleurs brand, neutres et sémantiques de la palette Nubia.
/// La typographie (google_fonts) n'est pas testée ici car elle nécessite
/// un accès réseau indisponible en CI.
///
/// Régénérer avec :
///   flutter test --update-goldens test/widget/nubia_theme_golden_test.dart
void main() {
  testWidgets('NubiaTheme light — golden snapshot', (tester) async {
    // Construit un ThemeData sans google_fonts pour éviter les appels
    // HTTP bloqués par TestWidgetsFlutterBinding.
    final testTheme = ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: NubiaColors.brand700,
        onPrimary: NubiaColors.n0,
        primaryContainer: NubiaColors.brand50,
        onPrimaryContainer: NubiaColors.brand800,
        secondary: NubiaColors.brand600,
        onSecondary: NubiaColors.n0,
        surface: NubiaColors.n0,
        onSurface: NubiaColors.n900,
        onSurfaceVariant: NubiaColors.n600,
        error: NubiaColors.dangerFg,
        onError: NubiaColors.n0,
        outline: NubiaColors.n300,
      ),
      extensions: <ThemeExtension<dynamic>>[NubiaTokens.light],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: const _ColorPalette(),
      ),
    );

    await expectLater(
      find.byType(_ColorPalette),
      matchesGoldenFile('goldens/nubia_theme_light.png'),
    );
  });
}

/// Affiche la palette de couleurs du thème Nubia en light mode.
///
/// Rend uniquement des blocs colorés pour éviter le chargement de polices
/// en CI.
class _ColorPalette extends StatelessWidget {
  const _ColorPalette();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    return Scaffold(
      backgroundColor: NubiaColors.n50,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Swatch(color: cs.primary),
            _Swatch(color: cs.primaryContainer),
            _Swatch(color: cs.onPrimaryContainer),
            _Swatch(color: cs.secondary),
            _Swatch(color: cs.surface),
            _Swatch(color: cs.error),
            _Swatch(color: tokens.successFg),
            _Swatch(color: tokens.successBg),
            _Swatch(color: tokens.warningFg),
            _Swatch(color: tokens.warningBg),
            _Swatch(color: tokens.dangerFg),
            _Swatch(color: tokens.dangerBg),
            _Swatch(color: tokens.infoFg),
            _Swatch(color: tokens.infoBg),
            _Swatch(color: tokens.accent),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}
