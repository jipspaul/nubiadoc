import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../../router/app_router.dart';
import '../../compliance/widgets/compliance_item_row.dart';
import '../compliance_alerts_summary_cubit.dart';

/// Carte « Alertes conformité » du tableau de bord (#7169) : items de
/// l'échéancier ARS/DMSM échus ou approchant l'échéance, lien vers l'écran
/// Conformité complet.
class ComplianceAlertsCard extends StatelessWidget {
  const ComplianceAlertsCard({super.key});

  /// Nombre de lignes affichées avant de renvoyer vers l'écran complet.
  static const int _maxRows = 5;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return NubiaCard(
      key: const Key('compliance_alerts_card'),
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
                  Icons.fact_check_outlined,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Alertes conformité',
                    style:
                        textTheme.titleMedium?.copyWith(color: cs.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  key: const Key('compliance_alerts_card_see_all'),
                  onPressed: () => context.push(AppRouter.compliance),
                  child: const Text('Voir tout'),
                ),
              ],
            ),
          ),
          BlocBuilder<ComplianceAlertsSummaryCubit, ComplianceAlertsSummaryState>(
            builder: (context, state) {
              return switch (state) {
                ComplianceAlertsSummaryLoading() => const Padding(
                    key: Key('compliance_alerts_card_loading'),
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: NubiaSkeletonLoader(height: 64, borderRadius: 8),
                  ),
                ComplianceAlertsSummaryError(:final message) => Padding(
                    key: const Key('compliance_alerts_card_error'),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(message, style: TextStyle(color: cs.error)),
                  ),
                ComplianceAlertsSummaryLoaded(:final alertingItems)
                    when alertingItems.isEmpty =>
                  Padding(
                    key: const Key('compliance_alerts_card_empty'),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(
                      'Aucune échéance de conformité en approche.',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ComplianceAlertsSummaryLoaded(:final alertingItems) =>
                  _ComplianceAlertRows(
                    items: alertingItems.take(_maxRows).toList(),
                  ),
              };
            },
          ),
        ],
      ),
    );
  }
}

class _ComplianceAlertRows extends StatelessWidget {
  const _ComplianceAlertRows({required this.items});

  final List<ComplianceItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, item) in items.indexed)
          ComplianceItemRow(
            item: item,
            showDivider: i < items.length - 1,
          ),
      ],
    );
  }
}
