import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'notification_route_resolver.dart';
import 'notifications_bloc.dart';
import 'notifications_event.dart';
import 'notifications_state.dart';

/// En-tête de l'onglet Notifications : titre, sous-titre "N non lues" et
/// action « Tout marquer lu ».
///
/// Doit être placée dans un [BlocProvider<NotificationsBloc>].
class NotificationsAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const NotificationsAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotificationsBloc, NotificationsState>(
      builder: (context, state) {
        final unreadCount = state is NotificationsLoaded
            ? state.unreadCount
            : null;
        return AppBar(
          titleSpacing: 0,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Notifications',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
              if (unreadCount != null)
                Text(
                  '$unreadCount ${unreadCount == 1 ? 'non lue' : 'non lues'}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: NubiaColors.n500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          actions: [
            if (unreadCount != null && unreadCount > 0)
              TextButton.icon(
                onPressed: () => context.read<NotificationsBloc>().add(
                  const NotificationMarkAllReadRequested(),
                ),
                icon: const Icon(Icons.done_all, color: NubiaColors.brand700),
                label: const Text(
                  'Tout marquer lu',
                  style: TextStyle(
                    color: NubiaColors.brand700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Page inbox des notifications patient.
///
/// Doit être placée dans un [BlocProvider<NotificationsBloc>].
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotificationsBloc, NotificationsState>(
      builder: (context, state) => switch (state) {
        NotificationsInitial() || NotificationsLoading() => const Center(
          key: Key('notifications_loading'),
          child: CircularProgressIndicator(),
        ),
        NotificationsError(:final message) => NubiaErrorWidget(
          key: const Key('notifications_error'),
          message: message,
          onRetry: () => context.read<NotificationsBloc>().add(
            const NotificationsLoadRequested(),
          ),
        ),
        NotificationsEmpty() => const NubiaEmptyState(
          key: Key('notifications_empty'),
          icon: Icons.notifications_off,
          title: 'Aucune notification',
          subtitle: 'Vous êtes à jour',
        ),
        NotificationsLoaded loaded => _NotificationsContent(state: loaded),
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _NotificationsContent extends StatefulWidget {
  const _NotificationsContent({required this.state});

  final NotificationsLoaded state;

  @override
  State<_NotificationsContent> createState() => _NotificationsContentState();
}

/// Facette sélectionnée : filtre de vue local, sans event bloc (pas d'appel
/// réseau supplémentaire — les compteurs sont dérivés de `state.notifications`).
class _NotificationsContentState extends State<_NotificationsContent> {
  NotificationType? _facet;

  static const _facets = <(String, NotificationType?)>[
    ('Toutes', null),
    ('Rendez-vous', NotificationType.appointment),
    ('Documents', NotificationType.document),
    ('Paiements', NotificationType.payment),
  ];

  @override
  Widget build(BuildContext context) {
    final notifications = widget.state.notifications;
    if (notifications.isEmpty) {
      return const NubiaEmptyState(
        key: Key('notifications_empty'),
        icon: Icons.notifications_off,
        title: 'Aucune notification',
        subtitle: 'Vous êtes à jour',
      );
    }
    final visible = _facet == null
        ? notifications
        : notifications.where((n) => n.type == _facet).toList();
    final rows = _groupedRows(visible);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, type) in _facets)
                NubiaChip(
                  key: Key('notif_filter_${type?.name ?? 'all'}'),
                  label: label,
                  count: type == null
                      ? notifications.length
                      : notifications.where((n) => n.type == type).length,
                  selected: _facet == type,
                  selectedBackground: NubiaColors.n900,
                  selectedForeground: Colors.white,
                  onTap: () => setState(() => _facet = type),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            key: const Key('notifications_list'),
            children: rows,
          ),
        ),
      ],
    );
  }

  /// Regroupe [visible] sous des en-têtes temporels (« Aujourd'hui »,
  /// « Cette semaine ») calculés côté client depuis `createdAt` — pas
  /// d'appel réseau supplémentaire. Un groupe vide ne rend aucun en-tête.
  List<Widget> _groupedRows(List<AppNotification> visible) {
    final today = DateTime.now();
    final todayItems = <AppNotification>[];
    final weekItems = <AppNotification>[];
    for (final notification in visible) {
      final createdAt = notification.createdAt;
      final isToday = createdAt.year == today.year &&
          createdAt.month == today.month &&
          createdAt.day == today.day;
      (isToday ? todayItems : weekItems).add(notification);
    }

    final rows = <Widget>[];
    void addGroup(Key key, String label, List<AppNotification> items) {
      if (items.isEmpty) return;
      rows.add(_NotificationGroupHeader(key: key, label: label));
      for (var i = 0; i < items.length; i++) {
        rows.add(_NotificationTile(notification: items[i]));
        if (i < items.length - 1) rows.add(const Divider(height: 1));
      }
    }

    addGroup(const Key('notif_group_today'), "Aujourd'hui", todayItems);
    addGroup(const Key('notif_group_week'), 'Cette semaine', weekItems);
    return rows;
  }
}

// ---------------------------------------------------------------------------

/// En-tête de section temporelle au-dessus d'un groupe de notifications
/// (maquette design-v2, écran Patient · Notifications).
class _NotificationGroupHeader extends StatelessWidget {
  const _NotificationGroupHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: NubiaColors.n50,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: NubiaColors.n400,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Teintes de pastille hors palette [NubiaColors] (verbatim maquette design-v2,
/// écran Patient · Notifications) : violet pour les rendez-vous, bleu pour la
/// pharmacie. Les autres familles réutilisent les tokens [NubiaColors].
class _NotificationFamilyColors {
  static const violetBg = Color(0xFFEDE9FE);
  static const violetFg = Color(0xFF6D28D9);
  static const blueBg = Color(0xFFE0F2FE);
  static const blueFg = Color(0xFF0369A1);
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _colorsFor(notification.type);
    final deepLink = notification.deepLink;
    final hasAction = deepLink != null && deepLink.isNotEmpty;
    final action = hasAction ? _actionFor(notification.type) : null;
    return ListTile(
      key: Key('notif_${notification.id}'),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(_iconFor(notification.type), color: foreground, size: 20),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              notification.title,
              style: TextStyle(
                fontWeight:
                    notification.read ? FontWeight.normal : FontWeight.bold,
              ),
            ),
          ),
          Text(
            NubiaDate.relative(notification.createdAt),
            style: TextStyle(
              fontSize: 11.5,
              color:
                  notification.read ? NubiaColors.n500 : NubiaColors.brand700,
              fontWeight:
                  notification.read ? FontWeight.normal : FontWeight.bold,
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(notification.body),
          if (action != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: NubiaButton(
                key: Key('notif_action_${notification.id}'),
                label: action.label,
                icon: action.icon,
                size: NubiaButtonSize.sm,
                variant: action.variant,
                onPressed: () => _handleAction(context, deepLink!),
              ),
            ),
          ],
        ],
      ),
      onTap: () => context.read<NotificationsBloc>().add(
        NotificationMarkReadRequested(notification.id),
      ),
    );
  }

  void _handleAction(BuildContext context, String deepLink) {
    context.read<NotificationsBloc>().add(
      NotificationMarkReadRequested(notification.id),
    );
    final route = NotificationRouteResolver.resolve(deepLink: deepLink);
    if (route != null) context.go(route);
  }

  static IconData _iconFor(NotificationType type) {
    return switch (type) {
      NotificationType.appointment => Icons.event_outlined,
      NotificationType.message => Icons.chat_bubble_outline,
      NotificationType.document => Icons.folder_outlined,
      NotificationType.payment => Icons.receipt_outlined,
      NotificationType.other => Icons.notifications_outlined,
    };
  }

  /// Bouton d'action sous le corps de la notification (maquette design-v2) :
  /// libellé + icône par famille, primaire pour la pharmacie (`other`,
  /// commandes click-and-collect), secondaire pour les autres.
  static ({String label, IconData icon, NubiaButtonVariant variant}) _actionFor(
    NotificationType type,
  ) {
    return switch (type) {
      NotificationType.other => (
          label: 'Afficher mon code',
          icon: Icons.qr_code_2,
          variant: NubiaButtonVariant.primary,
        ),
      NotificationType.message => (
          label: 'Répondre',
          icon: Icons.reply,
          variant: NubiaButtonVariant.secondary,
        ),
      NotificationType.appointment => (
          label: 'Voir le rendez-vous',
          icon: Icons.event_available,
          variant: NubiaButtonVariant.secondary,
        ),
      NotificationType.document => (
          label: 'Voir le document',
          icon: Icons.folder_outlined,
          variant: NubiaButtonVariant.secondary,
        ),
      NotificationType.payment => (
          label: 'Voir la facture',
          icon: Icons.receipt_outlined,
          variant: NubiaButtonVariant.secondary,
        ),
    };
  }

  /// Pastille (fond, icône) par famille de notification (maquette design-v2).
  static (Color background, Color foreground) _colorsFor(
    NotificationType type,
  ) {
    return switch (type) {
      NotificationType.appointment => (
        _NotificationFamilyColors.violetBg,
        _NotificationFamilyColors.violetFg,
      ),
      NotificationType.message => (NubiaColors.infoBg, NubiaColors.infoFg),
      NotificationType.document => (NubiaColors.brand50, NubiaColors.brand700),
      NotificationType.payment => (
        NubiaColors.warningBg,
        NubiaColors.warningFg,
      ),
      NotificationType.other => (
        _NotificationFamilyColors.blueBg,
        _NotificationFamilyColors.blueFg,
      ),
    };
  }
}
