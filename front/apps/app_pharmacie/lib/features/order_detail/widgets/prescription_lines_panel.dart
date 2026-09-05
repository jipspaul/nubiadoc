import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'prescription_line_tile.dart';

/// Panneau « lecture » de l'ordonnance (volet gauche) : bloc prescripteur
/// puis lignes lisibles (molécule, posologie en clair, quantité en gros à
/// droite). Le PDF reste accessible via « Voir l'original » dans l'en-tête
/// — un recours, plus le seul accès.
///
/// [rpps]/[prescribedAt]/[validUntil] : la donnée n'est pas encore plombée
/// jusqu'ici (ticket dédié) — `null` affiche un tiret, en attendant.
/// [prescriberName] est alimenté depuis [PharmacyOrder.prescriberName].
class PrescriptionLinesPanel extends StatelessWidget {
  const PrescriptionLinesPanel({
    super.key,
    required this.items,
    required this.onOpenDocument,
    this.prescriberName,
    this.rpps,
    this.prescribedAt,
    this.validUntil,
    this.preparedLineIndices = const {},
    this.onLinePreparedChanged,
  });

  final List<PrescriptionItem> items;
  final VoidCallback onOpenDocument;

  final String? prescriberName;
  final String? rpps;
  final DateTime? prescribedAt;
  final DateTime? validUntil;

  /// Index des lignes cochées « préparée ».
  final Set<int> preparedLineIndices;

  /// `null` désactive les cases (ex. commande déjà au-delà de `preparing`).
  final void Function(int index, bool prepared)? onLinePreparedChanged;

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
              const SizedBox(width: 8),
              _OriginalDocumentLink(onTap: onOpenDocument),
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
            PrescriptionLineTile(
              item: items[i],
              prepared: preparedLineIndices.contains(i),
              onPreparedChanged: onLinePreparedChanged == null
                  ? null
                  : (value) => onLinePreparedChanged!(i, value),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lien discret vers le PDF d'origine — recours, plus le seul accès (le PDF
/// appelle `core.openDocumentUrl` et quitte donc l'app).
class _OriginalDocumentLink extends StatelessWidget {
  const _OriginalDocumentLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const StadiumBorder(side: BorderSide(color: NubiaColors.n200)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('order_detail_open_document'),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.picture_as_pdf,
                size: 16,
                color: NubiaColors.brand700,
              ),
              SizedBox(width: 6),
              Text(
                'Voir l\'original',
                style: TextStyle(
                  color: NubiaColors.brand700,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
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
