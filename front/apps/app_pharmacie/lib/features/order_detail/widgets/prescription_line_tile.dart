import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'substitution_tags.dart';

/// Une ligne d'ordonnance : molécule (`label` + `form`) en gras, posologie
/// (`posology` + `duration`) en clair dessous, quantité (`quantity`) mise en
/// avant à droite, mentions substituable/non substituable en tags, et
/// l'encart d'alerte d'interaction (`interactionWarning`) si la ligne en
/// porte une. Case de préparation : ticket dédié (hors périmètre ici).
class PrescriptionLineTile extends StatelessWidget {
  const PrescriptionLineTile({super.key, required this.item});

  final PrescriptionItem item;

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final form = item.form;
    final name = (form == null || form.isEmpty)
        ? item.label
        : '${item.label} — $form';
    final posology = item.duration.isEmpty
        ? item.posology
        : '${item.posology}, ${item.duration}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(posology, style: theme.textTheme.bodySmall),
                const SizedBox(height: 6),
                SubstitutionTags(item: item),
                if (item.interactionWarning != null &&
                    item.interactionWarning!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _InteractionWarningBanner(
                    message: item.interactionWarning!,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            item.quantity,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFeatures: _tabular,
            ),
          ),
        ],
      ),
    );
  }
}

/// Encart d'alerte d'interaction médicamenteuse : purement informatif, ne
/// bloque ni ne désactive aucune action sur la ligne.
class _InteractionWarningBanner extends StatelessWidget {
  const _InteractionWarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      key: const Key('interaction_warning_banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.warningFg.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: tokens.warningFg),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: textTheme.bodySmall?.copyWith(color: tokens.warningFg),
                children: [
                  const TextSpan(
                    text: 'Interaction possible',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: ' — $message'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
