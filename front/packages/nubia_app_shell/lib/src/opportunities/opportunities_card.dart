import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Carte « opportunités du moment » (#7213, DP-F1.b) : les 5 catégories
/// exposées par `GET /v1/cabinet/opportunities` (#7214), partagée entre les
/// apps praticien/secrétariat comme les widgets de `ProShell`. Chaque ligne
/// est cliquable vers le devis / la facture / le patient de la catégorie —
/// la navigation dépend des routes de l'app hôte, donc laissée à
/// [onCategoryTap].
class OpportunitiesCard extends StatelessWidget {
  const OpportunitiesCard({
    super.key,
    required this.categories,
    this.onCategoryTap,
  });

  /// Les 5 catégories, dans l'ordre renvoyé par l'API.
  final List<OpportunityCategory> categories;

  /// Appelé au tap sur une ligne dont le compteur est non nul.
  final void Function(BuildContext context, OpportunityCategory category)?
      onCategoryTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final totalCount = categories.fold<int>(0, (sum, c) => sum + c.count);

    return NubiaCard(
      key: const Key('opportunities_card'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Opportunités du moment',
                    style:
                        textTheme.titleMedium?.copyWith(color: cs.onSurface),
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(
                  key: const Key('opportunities_card_total'),
                  label: '$totalCount',
                  variant: totalCount > 0
                      ? StatusPillVariant.warning
                      : StatusPillVariant.neutral,
                ),
              ],
            ),
          ),
          for (var i = 0; i < categories.length; i++)
            _OpportunityRow(
              category: categories[i],
              showDivider: i < categories.length - 1,
              onTap: onCategoryTap == null
                  ? null
                  : () => onCategoryTap!(context, categories[i]),
            ),
        ],
      ),
    );
  }
}

class _OpportunityRow extends StatelessWidget {
  const _OpportunityRow({
    required this.category,
    required this.showDivider,
    this.onTap,
  });

  final OpportunityCategory category;
  final bool showDivider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListRow(
      key: Key('opportunity_row_${category.kind}'),
      leading: _CategoryIcon(kind: category.kind),
      title: _labelFor(category.kind),
      subtitle: category.totalAmountCents != 0
          ? NubiaMoney.formatCents(category.totalAmountCents)
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusPill(
            label: '${category.count}',
            variant: category.count > 0
                ? StatusPillVariant.warning
                : StatusPillVariant.neutral,
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
        ],
      ),
      onTap: category.count > 0 ? onTap : null,
      showDivider: showDivider,
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: tokens.warningBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(_iconFor(kind), size: 18, color: tokens.warningFg),
    );
  }
}

/// Libellés des 5 catégories (doc17 §4, #7214).
String _labelFor(String kind) => switch (kind) {
      'quote_sent_no_response' => 'Devis envoyés sans réponse',
      'quote_accepted_no_appointment' => 'Devis acceptés sans RDV',
      'unpaid_invoice' => 'Factures impayées',
      'patient_no_next_appointment' => 'Patients sans prochain RDV',
      'birthday_today' => 'Anniversaires du jour',
      _ => kind,
    };

IconData _iconFor(String kind) => switch (kind) {
      'quote_sent_no_response' => Icons.send_outlined,
      'quote_accepted_no_appointment' => Icons.event_busy_outlined,
      'unpaid_invoice' => Icons.receipt_long_outlined,
      'patient_no_next_appointment' => Icons.event_available_outlined,
      'birthday_today' => Icons.cake_outlined,
      _ => Icons.info_outline,
    };
