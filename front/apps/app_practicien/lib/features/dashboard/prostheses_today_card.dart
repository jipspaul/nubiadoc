import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/app_router.dart';
import '../lab_work/lab_work_order_status_style.dart';
import 'prostheses_today_bloc.dart';

/// Initiales pour `NubiaAvatar`, même convention que
/// `lab_work_orders_page.dart` (#5058) : première lettre des deux premiers
/// mots (« Julie Martin » → « JM »).
String _initialsOf(String displayName) {
  final words = displayName.trim().split(RegExp(r'\s+'));
  final letters = words
      .where((w) => w.isNotEmpty)
      .take(2)
      .map((w) => w[0].toUpperCase());
  return letters.join();
}

/// Carte « Prothèses du jour » du tableau de bord praticien (#7207) : bons de
/// travaux dont le RDV de pose tombe aujourd'hui ou demain
/// (`GET /v1/cabinet/lab-work-orders/today`, #7208), en lecture seule — le
/// changement de statut se fait depuis l'écran de suivi labo
/// (`LabWorkOrdersPage`), pas ici.
class ProsthesesTodayCard extends StatelessWidget {
  const ProsthesesTodayCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return NubiaCard(
      key: const Key('prostheses_today_card'),
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
                  Icons.medical_services_outlined,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Prothèses du jour',
                    style:
                        textTheme.titleMedium?.copyWith(color: cs.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  key: const Key('prostheses_today_card_see_all'),
                  onPressed: () => context.push(AppRouter.labWorkOrders),
                  child: const Text('Voir le suivi labo'),
                ),
              ],
            ),
          ),
          BlocBuilder<ProsthesesTodayBloc, ProsthesesTodayState>(
            builder: (context, state) {
              return switch (state) {
                ProsthesesTodayInitial() ||
                ProsthesesTodayLoading() =>
                  const Padding(
                    key: Key('prostheses_today_card_loading'),
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: NubiaSkeletonLoader(height: 64, borderRadius: 8),
                  ),
                ProsthesesTodayError(:final message) => Padding(
                    key: const Key('prostheses_today_card_error'),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(message, style: TextStyle(color: cs.error)),
                  ),
                ProsthesesTodayLoaded(:final orders) when orders.isEmpty =>
                  const Padding(
                    key: Key('prostheses_today_card_empty'),
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: NubiaEmptyState(
                      icon: Icons.medical_services_outlined,
                      title: 'Aucune prothèse attendue aujourd\'hui',
                    ),
                  ),
                ProsthesesTodayLoaded(:final orders) =>
                  _ProsthesisRows(orders: orders),
              };
            },
          ),
        ],
      ),
    );
  }
}

class _ProsthesisRows extends StatelessWidget {
  const _ProsthesisRows({required this.orders});

  final List<TodayLabWorkOrder> orders;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, order) in orders.indexed)
          _ProsthesisRow(order: order, showDivider: i < orders.length - 1),
      ],
    );
  }
}

class _ProsthesisRow extends StatelessWidget {
  const _ProsthesisRow({required this.order, required this.showDivider});

  final TodayLabWorkOrder order;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      if (order.toothFdi != null) 'Dent ${order.toothFdi}',
      order.labName,
    ];

    return ListRow(
      key: Key('prosthesis_today_${order.id}'),
      leading: NubiaAvatar(
        initials: _initialsOf(order.patientDisplayName),
        radius: 16,
      ),
      title: order.patientDisplayName,
      subtitle: subtitleParts.join(' · '),
      trailing: StatusPill(
        label: kLabWorkOrderStatusLabels[order.status] ?? order.status,
        variant:
            kLabWorkOrderStatusVariants[order.status] ?? StatusPillVariant.info,
      ),
      showDivider: showDivider,
    );
  }
}
