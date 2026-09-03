import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Libellés des facettes de la barre d'outils (maquette design-v2, #6243) —
/// seuls les quatre statuts que le secrétariat traite au quotidien ont une
/// facette dédiée (`paid`/`cancelled` restent visibles en liste sans filtre
/// rapide, comme sur la maquette).
const _devisFacetLabels = {
  CabinetQuoteStatus.sent: 'À signer',
  CabinetQuoteStatus.draft: 'Brouillons',
  CabinetQuoteStatus.signed: 'Signés',
  CabinetQuoteStatus.expired: 'Expirés',
};

/// Rangée de facettes de statut de la barre d'outils de l'écran Devis
/// (#6243) : chips avec pastille de couleur + libellé + compteur. Cliquer
/// une facette filtre la liste sur ce statut ; re-cliquer réinitialise
/// (`onSelected` bascule) — même pattern que `stock_page.dart`
/// (`_StockStatusFacetBar`).
class DevisStatusFacetBar extends StatelessWidget {
  const DevisStatusFacetBar({
    super.key,
    required this.quotes,
    required this.selected,
    required this.onSelected,
  });

  /// Devis chargés (non filtrés par la recherche) — source des compteurs de
  /// chaque facette.
  final List<CabinetQuote> quotes;
  final CabinetQuoteStatus? selected;
  final ValueChanged<CabinetQuoteStatus> onSelected;

  Color _dotColor(NubiaTokens tokens, CabinetQuoteStatus status) {
    switch (status) {
      case CabinetQuoteStatus.sent:
        return tokens.warningFg;
      case CabinetQuoteStatus.signed:
        return tokens.successFg;
      case CabinetQuoteStatus.expired:
        return tokens.dangerFg;
      case CabinetQuoteStatus.draft:
      case CabinetQuoteStatus.paid:
      case CabinetQuoteStatus.cancelled:
        return tokens.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in _devisFacetLabels.entries)
          _DevisFacetChip(
            key: Key('devis_facet_${entry.key.name}'),
            label: entry.value,
            count: quotes.where((q) => q.status == entry.key).length,
            dotColor: _dotColor(tokens, entry.key),
            selected: entry.key == selected,
            onTap: () => onSelected(entry.key),
          ),
      ],
    );
  }
}

/// Une facette de la [DevisStatusFacetBar] : pastille de couleur, libellé et
/// compteur — même habillage que `_StatusFacetChip` de `stock_page.dart`
/// (fond/bordure `brand50`/`brand200` sélectionné).
class _DevisFacetChip extends StatelessWidget {
  const _DevisFacetChip({
    super.key,
    required this.label,
    required this.count,
    required this.dotColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color dotColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final foreground = selected
        ? NubiaColors.brand800
        : Theme.of(context).colorScheme.onSurface;

    return Semantics(
      toggled: selected,
      label: '$label ($count)',
      child: Material(
        color: selected ? NubiaColors.brand50 : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? NubiaColors.brand200 : tokens.borderDefault,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: dotColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: textTheme.labelMedium?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: foreground,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected ? NubiaColors.brand200 : NubiaColors.n100,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: textTheme.labelSmall?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color:
                          selected ? NubiaColors.brand800 : NubiaColors.n600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
