import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../pharma_messaging/pharma_messaging_bloc.dart';
import '../../pharma_messaging/pharma_messaging_state.dart';
import '../../stock/stock_bloc.dart';
import '../orders_bloc.dart';
import '../orders_state.dart';
import 'order_wait.dart';

/// Colonne latérale « À traiter » — agrège les signaux hors tableau de la
/// file des commandes (maquette design-v2, #4916, point 6) : commandes en
/// attente > 2 h, messages du cabinet non lus, demandes de stock reçues.
///
/// Cloisonnement strict : aucune donnée clinique (au-delà de l'ordonnance à
/// délivrer) n'est exposée ici.
class OrdersAside extends StatelessWidget {
  const OrdersAside({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final ordersState = context.watch<OrdersBloc>().state;
    final messagingState = context.watch<PharmaMessagingBloc>().state;
    final stockState = context.watch<StockBloc>().state;

    final entries = <_AsideEntry?>[
      if (ordersState is OrdersLoaded) _waitingEntry(ordersState.orders, tokens),
      if (messagingState is PharmaMessagingConversationsLoaded)
        _messagesEntry(messagingState.conversations, tokens),
      if (stockState is StockLoaded) _stockEntry(stockState.requests, tokens),
      // « Lignes en rupture » suppose un état par ligne (disponible/rupture)
      // qui n'existe pas sur PharmacyOrder — dépend d'un ticket data séparé.
      // Tant qu'il n'est pas livré, le bloc reste masqué (jamais de valeur
      // inventée, cf. #4916).
      _stockoutEntry(),
    ].whereType<_AsideEntry>().toList();

    return DecoratedBox(
      key: const Key('orders_aside'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(left: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text(
                  'À traiter',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                NubiaBadge.count(
                  key: const Key('orders_aside_total_badge'),
                  count: entries.length,
                ),
              ],
            ),
          ),
          for (final entry in entries)
            ListRow(
              leading: Icon(entry.icon, color: entry.iconColor),
              title: entry.title,
              subtitle: entry.subtitle,
              trailing: NubiaBadge.count(
                count: entry.badgeCount,
                variant: entry.badgeVariant,
              ),
            ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: _PrivacyNotice(),
          ),
        ],
      ),
    );
  }
}

class _AsideEntry {
  const _AsideEntry({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.badgeCount,
    required this.badgeVariant,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final int badgeCount;
  final NubiaBadgeVariant badgeVariant;
}

/// « Commandes en attente > 2 h » — même seuil que l'escalade de la file
/// (`dangerThresholdMinutes`, `order_wait.dart`), recalculé côté client.
_AsideEntry? _waitingEntry(List<PharmacyOrder> orders, NubiaTokens tokens) {
  final count =
      orders.where((o) => orderWaitOf(o).tone == OrderWaitTone.danger).length;
  if (count == 0) return null;
  return _AsideEntry(
    icon: Icons.schedule,
    iconColor: tokens.dangerFg,
    title: 'Commandes en attente > 2 h',
    subtitle: count == 1 ? '1 patient concerné' : '$count patients concernés',
    badgeCount: count,
    badgeVariant: NubiaBadgeVariant.error,
  );
}

/// « Messages du cabinet » — non lus, toutes conversations confondues.
_AsideEntry? _messagesEntry(
  List<CabinetConversation> conversations,
  NubiaTokens tokens,
) {
  final unread = conversations.where((c) => c.unreadCount > 0).toList()
    ..sort((a, b) => b.unreadCount.compareTo(a.unreadCount));
  final total = unread.fold<int>(0, (sum, c) => sum + c.unreadCount);
  if (total == 0) return null;
  return _AsideEntry(
    icon: Icons.chat_bubble,
    iconColor: tokens.infoFg,
    title: 'Messages du cabinet',
    subtitle: '${unread.first.patientName} · non lus',
    badgeCount: total,
    badgeVariant: NubiaBadgeVariant.info,
  );
}

/// « Demandes de stock » — reçues du cabinet, en attente de réponse.
_AsideEntry? _stockEntry(List<StockRequest> requests, NubiaTokens tokens) {
  final pending =
      requests.where((r) => r.status == StockRequestStatus.sent).length;
  if (pending == 0) return null;
  return _AsideEntry(
    icon: Icons.inventory_2,
    iconColor: tokens.primarySubtleFg,
    title: 'Demandes de stock',
    subtitle: 'reçues du cabinet',
    badgeCount: pending,
    badgeVariant: NubiaBadgeVariant.neutral,
  );
}

_AsideEntry? _stockoutEntry() => null;

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Text(
      "La file n'affiche aucune donnée clinique au-delà de l'ordonnance à "
      'délivrer : ni antécédents, ni motif de consultation.',
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: tokens.textTertiary),
    );
  }
}
