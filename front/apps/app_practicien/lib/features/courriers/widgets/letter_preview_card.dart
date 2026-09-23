import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Aperçu client (best-effort) du courrier composé (#7196) : le corps rendu
/// authoritaire vient de `POST .../letters` (aucune route de prévisualisation
/// dédiée côté API, cf. `api/src/letters.rs`) — ce panneau substitue
/// localement ce qu'il connaît déjà (patient, date du jour, champs libres
/// saisis) et laisse les autres placeholders visibles entre crochets, résolus
/// uniquement à la génération.
class LetterPreviewCard extends StatelessWidget {
  const LetterPreviewCard({
    super.key,
    required this.templateName,
    required this.renderedBody,
    this.isDocxSource = false,
  });

  /// `null` tant qu'aucun modèle n'est choisi.
  final String? templateName;
  final String? renderedBody;

  /// `true` pour un modèle importé `.docx` (#7157/#7156) : `renderedBody`
  /// vaut alors toujours `''` (aucun `bodyTemplate` exploitable côté
  /// client), donc ce panneau signale de tester le rendu via « Générer »
  /// plutôt que d'afficher un encart vide trompeur.
  final bool isDocxSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = theme.extension<NubiaTokens>()!;

    return NubiaCard(
      key: const Key('letter_preview_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.preview, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'Aperçu du courrier',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isDocxSource)
            Text(
              'Aperçu indisponible pour un modèle Word — utilisez '
              '« Générer et ajouter aux documents » pour tester le rendu.',
              key: const Key('letter_preview_docx_notice'),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            )
          else if (renderedBody == null || templateName == null)
            Text(
              'Choisissez un modèle pour voir l\'aperçu.',
              key: const Key('letter_preview_empty'),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            )
          else
            Container(
              key: const Key('letter_preview_body'),
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NubiaColors.n0,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Text(
                renderedBody!,
                style:
                    theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
              ),
            ),
        ],
      ),
    );
  }
}
