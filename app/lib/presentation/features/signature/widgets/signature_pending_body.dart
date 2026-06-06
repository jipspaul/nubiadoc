import 'package:flutter/material.dart';

/// Corps affiché quand la signature est en attente de démarrage.
///
/// Affiche un texte d'explication et le bouton "Signer".
class SignaturePendingBody extends StatelessWidget {
  const SignaturePendingBody({super.key, required this.onSign});

  final VoidCallback onSign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.draw_rounded,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Signature électronique',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Vous allez être redirigé vers Yousign pour signer ce document de façon sécurisée (eIDAS).',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              key: const Key('sign_button'),
              onPressed: onSign,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Signer le document'),
            ),
          ],
        ),
      ),
    );
  }
}
