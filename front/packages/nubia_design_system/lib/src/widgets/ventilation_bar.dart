import 'package:flutter/material.dart';
import 'package:nubia_design_system/src/format/money_format.dart';
import 'package:nubia_design_system/src/theme/nubia_colors.dart';
import 'package:nubia_design_system/src/theme/nubia_tokens.dart';
import 'package:nubia_design_system/src/widgets/nubia_card.dart';

/// Barre de ventilation Total → Reste à charge (#5234, extraite en composant
/// DS pour l'app Secrétariat en #5091) : un track à trois segments
/// (AMO / AMC / reste à charge) suivi d'une légende qui soustrait ligne à
/// ligne jusqu'au montant final.
///
/// Ne prend que des montants (pas d'entité `Quote`/`CabinetQuote`) pour
/// rester réutilisable par n'importe quelle app sans dépendance à
/// `nubia_domain` : chaque app agrège ses lignes (ex.
/// `items.amoShareTotalCents` côté `nubia_domain`) puis passe le résultat
/// ici, garantissant le même calcul et le même vocabulaire AMO/AMC partout.
///
/// Le nom de la mutuelle n'est pas exposé par le back : la ligne AMC reste
/// au libellé générique « Mutuelle ».
class VentilationBar extends StatelessWidget {
  const VentilationBar({
    super.key,
    required this.amoCents,
    required this.amcCents,
    required this.racCents,
    required this.racLabel,
  });

  final int amoCents;
  final int amcCents;
  final int racCents;

  /// Libellé de la ligne totale (ex. « Reste à votre charge » côté Patient,
  /// « Reste à charge » côté Secrétariat).
  final String racLabel;

  @override
  Widget build(BuildContext context) {
    // Rien à ventiler (devis brouillon sans lignes ni reste à charge connu).
    if (amoCents + amcCents + racCents <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = theme.extension<NubiaTokens>()!;

    return NubiaCard(
      key: const Key('ventilation_bar'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _VentilationTrack(
            amoCents: amoCents,
            amcCents: amcCents,
            racCents: racCents,
          ),
          const SizedBox(height: 14),
          _VentilationLegendLine(
            key: const Key('ventilation_legend_amo'),
            label: 'Assurance Maladie (AMO)',
            value: formatQuoteCents(-amoCents),
          ),
          Divider(height: 17, thickness: 1, color: tokens.borderSubtle),
          _VentilationLegendLine(
            key: const Key('ventilation_legend_amc'),
            label: 'Mutuelle',
            value: formatQuoteCents(-amcCents),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: NubiaColors.n300, width: 1.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        racLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      formatQuoteCents(racCents),
                      key: const Key('ventilation_rac_value'),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 19,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Track à 3 segments contigus (gap 2px) — largeurs ∝ (AMO, AMC, RAC), la
/// somme des trois fait toujours 100 % de la piste.
class _VentilationTrack extends StatelessWidget {
  const _VentilationTrack({
    required this.amoCents,
    required this.amcCents,
    required this.racCents,
  });

  final int amoCents;
  final int amcCents;
  final int racCents;

  static const _height = 14.0;
  static const _radius = 7.0;
  static const _gap = 2.0;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: SizedBox(
        height: _height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: amoCents,
              child: const ColoredBox(
                key: Key('ventilation_segment_amo'),
                color: NubiaColors.brand600,
              ),
            ),
            const SizedBox(width: _gap),
            Expanded(
              flex: amcCents,
              child: const ColoredBox(
                key: Key('ventilation_segment_amc'),
                color: NubiaColors.brand200,
              ),
            ),
            const SizedBox(width: _gap),
            Expanded(
              flex: racCents,
              child: const ColoredBox(
                key: Key('ventilation_segment_rac'),
                color: NubiaColors.n900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une ligne de légende (libellé + montant soustrait, tabulaire).
class _VentilationLegendLine extends StatelessWidget {
  const _VentilationLegendLine({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}
