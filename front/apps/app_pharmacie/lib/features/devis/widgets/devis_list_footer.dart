import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Agrégats affichés sur le point extérieur du tableau ; regroupés ici pour
/// rester testables indépendamment du widget.
@immutable
class DevisFooterStats {
  const DevisFooterStats({
    required this.displayedCount,
    required this.totalCount,
    this.acceptanceRatePercent,
    this.averageResponseDays,
  });

  final int displayedCount;
  final int totalCount;

  /// `null` si aucun devis n'a encore été tranché (accepté/refusé/expiré).
  final int? acceptanceRatePercent;

  /// `null` si aucun devis envoyé n'a reçu de réponse du patient.
  final double? averageResponseDays;

  factory DevisFooterStats.of(
    List<PharmacyQuote> allQuotes, {
    required int displayedCount,
  }) {
    var decided = 0;
    var accepted = 0;
    var responseDaysSum = 0.0;
    var responded = 0;
    for (final quote in allQuotes) {
      if (quote.status == PharmacyQuoteStatus.accepted ||
          quote.status == PharmacyQuoteStatus.refused ||
          quote.status == PharmacyQuoteStatus.expired) {
        decided++;
        if (quote.status == PharmacyQuoteStatus.accepted) accepted++;
      }
      final sentAt = quote.sentAt;
      final decidedAt = quote.decidedAt;
      if ((quote.status == PharmacyQuoteStatus.accepted ||
              quote.status == PharmacyQuoteStatus.refused) &&
          sentAt != null &&
          decidedAt != null) {
        responseDaysSum +=
            decidedAt.difference(sentAt).inMinutes / (24 * 60);
        responded++;
      }
    }
    return DevisFooterStats(
      displayedCount: displayedCount,
      totalCount: allQuotes.length,
      acceptanceRatePercent:
          decided == 0 ? null : ((accepted / decided) * 100).round(),
      averageResponseDays: responded == 0 ? null : responseDaysSum / responded,
    );
  }
}

/// Pied de liste du tableau devis d'officine (design-v2, écart #4 de la QA
/// #6454) : « N devis affichés sur M · Taux d'acceptation : X % · Délai
/// moyen de réponse : Y j », absent jusqu'ici alors que l'écran secrétariat
/// équivalent l'a déjà.
class DevisListFooter extends StatelessWidget {
  const DevisListFooter({super.key, required this.stats});

  final DevisFooterStats stats;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: tokens.textTertiary,
        );
    final strongStyle = style?.copyWith(
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurface,
    );
    final rate = stats.acceptanceRatePercent;
    final avgDays = stats.averageResponseDays;

    return Container(
      key: const Key('devis_list_footer'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          Text.rich(
            TextSpan(style: style, children: [
              TextSpan(text: '${stats.displayedCount}', style: strongStyle),
              TextSpan(text: ' devis affichés sur ${stats.totalCount}'),
            ]),
          ),
          Text.rich(
            TextSpan(style: style, children: [
              const TextSpan(text: "Taux d'acceptation : "),
              TextSpan(
                text: rate == null ? '—' : '$rate %',
                style: strongStyle,
              ),
            ]),
          ),
          Text.rich(
            TextSpan(style: style, children: [
              const TextSpan(text: 'Délai moyen de réponse : '),
              TextSpan(
                text: avgDays == null ? '—' : '${_formatDays(avgDays)} j',
                style: strongStyle,
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

String _formatDays(double days) => days.toStringAsFixed(1).replaceAll('.', ',');
