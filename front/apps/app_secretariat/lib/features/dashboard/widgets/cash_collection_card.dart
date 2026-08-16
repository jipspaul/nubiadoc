import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../cash_collection_cubit.dart';

/// Carte « Encaissements du jour » (#5382, maquette design-v2 : « L'argent
/// du jour ») : encaissé aujourd'hui, reste à encaisser avant la fermeture,
/// impayés du cabinet — l'information de caisse qui manquait au tableau de
/// bord. Montants via `formatQuoteCents` (#4888, jamais de format euro
/// local dupliqué).
class CashCollectionCard extends StatelessWidget {
  const CashCollectionCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return NubiaCard(
      key: const Key('cash_collection_card'),
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
                  Icons.account_balance_wallet_outlined,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'Encaissements du jour',
                  style: textTheme.titleMedium?.copyWith(color: cs.onSurface),
                ),
              ],
            ),
          ),
          BlocBuilder<CashCollectionCubit, CashCollectionState>(
            builder: (context, state) => switch (state) {
              CashCollectionLoading() => const Padding(
                  key: Key('cash_collection_loading'),
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: NubiaSkeletonLoader(height: 120, borderRadius: 8),
                ),
              CashCollectionError(:final message) => Padding(
                  key: const Key('cash_collection_error'),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    message,
                    style: textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              CashCollectionLoaded(:final summary) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListRow(
                      key: const Key('cash_collected_today_row'),
                      title: 'Encaissé aujourd’hui',
                      subtitle:
                          '${summary.collectedTodayPaymentCount} paiement(s)',
                      trailing: _AmountText(
                        cents: summary.collectedTodayCents,
                        color: cs.primary,
                      ),
                    ),
                    ListRow(
                      key: const Key('cash_remaining_today_row'),
                      title: 'Reste à encaisser',
                      subtitle: '${summary.remainingTodayPatientCount} '
                          'patient(s) avant ${summary.closingHour}h',
                      trailing: _AmountText(
                        cents: summary.remainingTodayCents,
                        color: cs.onSurface,
                      ),
                    ),
                    ListRow(
                      key: const Key('cash_unpaid_row'),
                      title: 'Impayés du cabinet',
                      subtitle:
                          '${summary.unpaidPatientCount} patient(s) concerné(s)',
                      trailing: _AmountText(
                        cents: summary.unpaidCents,
                        color: tokens.dangerFg,
                      ),
                      showDivider: false,
                    ),
                  ],
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _AmountText extends StatelessWidget {
  const _AmountText({required this.cents, required this.color});

  final int cents;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      formatQuoteCents(cents, alwaysShowDecimals: true),
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
            fontFeatures: tabularFigures,
          ),
    );
  }
}
