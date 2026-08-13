import 'package:flutter/material.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'substitution_tags.dart';

/// Une ligne d'ordonnance : molécule (`label` + `form`) en gras, posologie
/// (`posology` + `duration`) en clair dessous, quantité (`quantity`) mise en
/// avant à droite, mentions substituable/non substituable en tags. Alerte
/// interaction et case de préparation : tickets dédiés (hors périmètre ici).
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
