// lib/presentation/widgets/status_pill.dart
import 'package:flutter/material.dart';
import 'package:nubia_patient/presentation/theme/nubia_tokens.dart';

/// Variants sémantiques du [StatusPill].
enum StatusPillVariant {
  info,
  success,
  warning,
  error,
}

/// Pill d'état : étiquette colorée avec fond sémantique.
///
/// Utilisée pour représenter un statut lisible (ex. « Confirmé », « Annulé »,
/// « En attente »).  Les couleurs proviennent de [NubiaTokens].
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.variant,
  });

  final String label;
  final StatusPillVariant variant;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    final Color bg;
    final Color fg;

    switch (variant) {
      case StatusPillVariant.info:
        bg = tokens.infoBg;
        fg = tokens.infoFg;
      case StatusPillVariant.success:
        bg = tokens.successBg;
        fg = tokens.successFg;
      case StatusPillVariant.warning:
        bg = tokens.warningBg;
        fg = tokens.warningFg;
      case StatusPillVariant.error:
        bg = tokens.dangerBg;
        fg = tokens.dangerFg;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}
