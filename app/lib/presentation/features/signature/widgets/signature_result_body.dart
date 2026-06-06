import 'package:flutter/material.dart';

/// Corps affiché pour les états terminaux ou en-cours de la signature
/// (en cours, signé, échec).
///
/// Affiche une icône, un message et optionnellement une couleur de surbrillance.
class SignatureResultBody extends StatelessWidget {
  const SignatureResultBody({
    super.key,
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;

  /// Couleur de l'icône et du texte. Si `null`, utilise la couleur primaire.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedColor = color ?? theme.colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: resolvedColor),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.bodyLarge?.copyWith(color: resolvedColor),
              textAlign: TextAlign.center,
              key: const Key('signature_status_text'),
            ),
          ],
        ),
      ),
    );
  }
}
