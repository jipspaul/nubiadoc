// lib/presentation/widgets/nubia_inline_error.dart
import 'package:flutter/material.dart';
import 'package:nubia_design_system/src/theme/nubia_tokens.dart';

/// Bandeau d'erreur inline non bloquant.
///
/// Contrairement à [NubiaErrorWidget] (plein écran, réservé au chargement
/// initial), [NubiaInlineError] s'affiche au-dessus d'un contenu déjà
/// chargé : un échec de rechargement ne doit jamais faire perdre à
/// l'utilisateur la liste/vue déjà affichée.
///
/// - [message] : description de l'erreur.
/// - [onRetry] : callback du bouton Réessayer. Si null, le bouton est masqué.
class NubiaInlineError extends StatelessWidget {
  const NubiaInlineError({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.dangerBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: tokens.dangerFg),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.dangerFg,
                    fontWeight: FontWeight.w500,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: tokens.dangerFg),
              child: const Text('Réessayer'),
            ),
        ],
      ),
    );
  }
}
