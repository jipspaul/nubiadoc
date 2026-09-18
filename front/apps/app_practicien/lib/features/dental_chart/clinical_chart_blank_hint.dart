//! Appel à l'action affiché en tête du schéma dentaire et du bilan
//! parodontal quand le patient n'en a pas encore (#6780) : l'API répond
//! `updated_at`/`measured_at` `null` et un contenu vide — c'est l'état
//! initial normal, et ces écrans sont précisément ceux qui créent le premier
//! enregistrement. Le bandeau nomme la situation et dit quoi faire ; il
//! disparaît après le premier enregistrement (`isBlank` de l'état `Loaded`).

import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

class ClinicalChartBlankHint extends StatelessWidget {
  const ClinicalChartBlankHint({
    super.key,
    required this.title,
    required this.message,
  });

  /// Ex. « Aucun schéma dentaire enregistré ».
  final String title;

  /// Ce que le praticien doit faire pour créer le premier enregistrement.
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>();
    return NubiaCard(
      backgroundColor: tokens?.primarySubtleBg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(message, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
