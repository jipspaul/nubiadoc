import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'prescription_line_tile.dart';

/// Panneau « lecture » de l'ordonnance (volet gauche) : bloc prescripteur
/// puis lignes lisibles (molécule, posologie en clair, quantité en gros à
/// droite). Le PDF (« Voir l'original ») reste le recours à côté, ticket
/// dédié — ce panneau ne le remplace pas.
///
/// [prescriberName]/[rpps]/[prescribedAt]/[validUntil] : la donnée n'est pas
/// encore plombée jusqu'ici (ticket dédié) — `null` affiche un tiret, en
/// attendant.
class PrescriptionLinesPanel extends StatelessWidget {
  const PrescriptionLinesPanel({
    super.key,
    required this.items,
    this.prescriberName,
    this.rpps,
    this.prescribedAt,
    this.validUntil,
  });

  final List<PrescriptionItem> items;
  final String? prescriberName;
  final String? rpps;
  final DateTime? prescribedAt;
  final DateTime? validUntil;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    final locale = MaterialLocalizations.of(context);

    String formatDate(DateTime? value) =>
        value == null ? '—' : locale.formatShortDate(value.toLocal());

    return NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.medication,
                  size: 20, color: NubiaColors.brand700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ordonnance — ${items.length} '
                  'ligne${items.length > 1 ? 's' : ''}',
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _PrescriberField(
                  label: 'Prescripteur',
                  value: prescriberName ?? '—',
                ),
              ),
              Expanded(
                child: _PrescriberField(label: 'RPPS', value: rpps ?? '—'),
              ),
              Expanded(
                child: _PrescriberField(
                  label: 'Prescrite le',
                  value: formatDate(prescribedAt),
                ),
              ),
              Expanded(
                child: _PrescriberField(
                  label: 'Valable jusqu\'au',
                  value: formatDate(validUntil),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
            PrescriptionLineTile(item: items[i]),
          ],
        ],
      ),
    );
  }
}

class _PrescriberField extends StatelessWidget {
  const _PrescriberField({required this.label, required this.value});

  final String label;
  final String value;

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFeatures: _tabular,
          ),
        ),
      ],
    );
  }
}
