// lib/presentation/widgets/amount_header.dart
import 'package:flutter/material.dart';
import 'package:nubia_design_system/src/theme/nubia_tokens.dart';

/// En-tête montant du WEDGE financier.
///
/// Affiche un [amount] en style `h2` (headlineMedium) avec chiffres tabulaires
/// (`FontFeature.tabularFigures()`), un [label] au-dessus et une [caption]
/// optionnelle en dessous. En option, un bandeau « reste à charge » (fond
/// `brand/50` via `primarySubtleBg`) affiche [remainingAmount].
///
/// - [label] : intitulé du montant (ex. « Total du plan de soins »).
/// - [amount] : montant formaté (ex. « 2 060 € »), rendu en chiffres tabulaires.
/// - [caption] : sous-titre optionnel (ex. « Plan de soins · Dr Lefèvre »).
/// - [remainingLabel] / [remainingAmount] : bandeau reste à charge optionnel.
/// - [remainingCaption] : précision optionnelle (ex. « après remboursements »).
///
/// Réfs mockup : `design/mockups/lib/screens-wedge.jsx` (AmountHeader + bandeau
/// reste à charge `--primary-subtle-bg`).
class AmountHeader extends StatelessWidget {
  const AmountHeader({
    super.key,
    required this.label,
    required this.amount,
    this.caption,
    this.remainingLabel,
    this.remainingAmount,
    this.remainingCaption,
  });

  final String label;
  final String amount;
  final String? caption;
  final String? remainingLabel;
  final String? remainingAmount;
  final String? remainingCaption;

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = theme.extension<NubiaTokens>()!;
    final bool hasRemaining = remainingLabel != null && remainingAmount != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.textTertiary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          amount,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: cs.onSurface,
            fontFeatures: _tabular,
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 4),
          Text(
            caption!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
        if (hasRemaining) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: tokens.primarySubtleBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        remainingLabel!,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: tokens.primarySubtleFg,
                        ),
                      ),
                      if (remainingCaption != null)
                        Text(
                          remainingCaption!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: tokens.primarySubtleFg.withValues(
                              alpha: 0.8,
                            ),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  remainingAmount!,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: tokens.primarySubtleFg,
                    fontFeatures: _tabular,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
