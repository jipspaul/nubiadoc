import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Facette de filtre par statut au-dessus de la liste de devis (#4898).
///
/// `refusedOrExpired` agrège `refused` et `expired` : côté design ces deux
/// statuts partagent déjà le variant `error` sur la carte (`_variants` dans
/// `devis_page.dart`) — la facette reprend le même regroupement.
enum DevisStatusFacet {
  all,
  draft,
  sent,
  accepted,
  refusedOrExpired;

  static const _labels = {
    DevisStatusFacet.all: 'Tous',
    DevisStatusFacet.draft: 'Brouillons',
    DevisStatusFacet.sent: 'Envoyés',
    DevisStatusFacet.accepted: 'Acceptés',
    DevisStatusFacet.refusedOrExpired: 'Refusés / expirés',
  };

  String get label => _labels[this]!;

  bool matches(PharmacyQuote quote) {
    return switch (this) {
      DevisStatusFacet.all => true,
      DevisStatusFacet.draft => quote.status == PharmacyQuoteStatus.draft,
      DevisStatusFacet.sent => quote.status == PharmacyQuoteStatus.sent,
      DevisStatusFacet.accepted =>
        quote.status == PharmacyQuoteStatus.accepted,
      DevisStatusFacet.refusedOrExpired =>
        quote.status == PharmacyQuoteStatus.refused ||
            quote.status == PharmacyQuoteStatus.expired,
    };
  }

  /// Couleur de la pastille de statut — `null` pour « Tous », qui n'en a pas.
  Color? dotColor(NubiaTokens tokens) {
    return switch (this) {
      DevisStatusFacet.all => null,
      DevisStatusFacet.draft => tokens.textTertiary,
      DevisStatusFacet.sent => tokens.warningFg,
      DevisStatusFacet.accepted => tokens.successFg,
      DevisStatusFacet.refusedOrExpired => tokens.dangerFg,
    };
  }
}

/// Rangée de facettes de filtre par statut, en tête de la liste de devis.
///
/// « Tous » est actif par défaut ; sélectionner une facette restreint la
/// liste au(x) statut(s) correspondant(s) — filtre purement UI, le
/// chargement (`PharmacyDevisLoaded`) n'est pas affecté.
class DevisStatusFacetBar extends StatelessWidget {
  const DevisStatusFacetBar({
    super.key,
    required this.quotes,
    required this.selected,
    required this.onSelected,
  });

  final List<PharmacyQuote> quotes;
  final DevisStatusFacet selected;
  final ValueChanged<DevisStatusFacet> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final facet in DevisStatusFacet.values) ...[
              if (facet != DevisStatusFacet.values.first)
                const SizedBox(width: 8),
              _DevisStatusFacetChip(
                facet: facet,
                count: quotes.where(facet.matches).length,
                selected: facet == selected,
                onTap: () => onSelected(facet),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Une facette de la [DevisStatusFacetBar] : libellé, pastille de couleur de
/// statut et compteur. Sélectionnée : fond sombre plein (`n900`), comme
/// « Tous » sur la maquette ; sinon contour clair.
class _DevisStatusFacetChip extends StatelessWidget {
  const _DevisStatusFacetChip({
    required this.facet,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final DevisStatusFacet facet;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    final dotColor = facet.dotColor(tokens);

    final Color foreground =
        selected ? NubiaColors.n0 : theme.colorScheme.onSurface;
    final Color countBackground = selected ? NubiaColors.n700 : NubiaColors.n100;
    final Color countForeground = selected ? NubiaColors.n0 : NubiaColors.n600;

    return Semantics(
      button: true,
      selected: selected,
      label: '${facet.label} ($count)',
      child: Material(
        color: selected ? NubiaColors.n900 : theme.colorScheme.surface,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? NubiaColors.n900 : tokens.borderSubtle,
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
                if (dotColor != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  facet.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: countBackground,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '$count',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: countForeground,
                      fontWeight: FontWeight.w600,
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
