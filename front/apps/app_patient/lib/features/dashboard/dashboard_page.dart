import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../router/app_router.dart';
import '../appointments/appointments_bloc.dart';
import '../appointments/appointments_page.dart';
import '../documents/documents_page.dart';
import '../mes_rdv/mes_rdv_page.dart';
import '../messaging/messaging_bloc.dart';
import '../messaging/messaging_event.dart';
import '../messaging/messaging_page.dart';
import '../messaging/messaging_state.dart';
import '../notifications/notifications_bloc.dart';
import '../notifications/notifications_event.dart';
import '../notifications/notifications_state.dart';
import '../profile/profile_bloc.dart';
import '../profile/profile_event.dart';
import '../profile/profile_page.dart';

/// Patient home shell: 5-tab bottom nav (Rechercher / Mes RDV / Messages /
/// Documents / Profil).
///
/// L'onglet « Rechercher » affiche l'annuaire ([AppointmentsPage] : barre de
/// recherche + carte + liste des praticiens). Le shell lui-même ne doit pas
/// dépendre d'un appel réseau : un échec d'un onglet ne doit pas bloquer
/// l'accès aux autres (Mes RDV, Messages, Documents, Profil).
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _index = 0;
  late final MessagingBloc _messagingBloc;
  late final NotificationsBloc _notificationsBloc;

  static const _tabs = [
    (label: 'Rechercher', icon: Icons.search),
    (label: 'Mes RDV', icon: Icons.event_outlined),
    (label: 'Messages', icon: Icons.chat_bubble_outline),
    (label: 'Documents', icon: Icons.folder_outlined),
    (label: 'Profil', icon: Icons.person_outline),
  ];

  @override
  void initState() {
    super.initState();
    _messagingBloc = GetIt.instance<MessagingBloc>()
      ..add(const MessagingConversationsLoadRequested());
    _notificationsBloc = GetIt.instance<NotificationsBloc>()
      ..add(const NotificationsLoadRequested());
  }

  @override
  void dispose() {
    _messagingBloc.close();
    _notificationsBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _messagingBloc),
        BlocProvider.value(value: _notificationsBloc),
      ],
      child: Scaffold(
        appBar: NubiaAppBar(
          title: _tabs[_index].label,
          actions: [
            _HeaderIconButton(
              key: const Key('header_action_search'),
              icon: Icons.search,
              tooltip: 'Annuaire',
              onPressed: () => setState(() => _index = 0),
            ),
            BlocSelector<NotificationsBloc, NotificationsState, bool>(
              selector: (s) => s is NotificationsLoaded && s.unreadCount > 0,
              builder: (context, hasUnread) => _HeaderIconButton(
                key: const Key('header_action_notifications'),
                icon: Icons.notifications_outlined,
                tooltip: 'Notifications',
                showDot: hasUnread,
                onPressed: () => context.push(AppRouter.notifications),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: switch (_index) {
          0 => BlocProvider(
              create: (_) => GetIt.instance<AppointmentsBloc>(),
              child: AppointmentsPage(
                onViewMyAppointments: () => setState(() => _index = 1),
              ),
            ),
          1 => const MesRdvPage(),
          2 => const MessagingPage(),
          3 => const DocumentsPage(),
          4 => BlocProvider(
              create: (_) => GetIt.instance<ProfileBloc>()
                ..add(const ProfileLoadRequested()),
              child: const ProfilePage(),
            ),
          _ => Center(
              child: NubiaEmptyState(
                icon: Icons.construction_outlined,
                title: _tabs[_index].label,
                subtitle: 'Écran en cours de développement.',
              ),
            ),
        },
        bottomNavigationBar: BlocSelector<MessagingBloc, MessagingState, int>(
          selector: (s) => s is MessagingConversationsLoaded
              ? s.conversations.fold(0, (acc, c) => acc + c.unreadCount)
              : 0,
          builder: (context, unreadCount) {
            return NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (int i = 0; i < _tabs.length; i++)
                  NavigationDestination(
                    icon: i == 2
                        ? Badge.count(
                            count: unreadCount,
                            isLabelVisible: unreadCount > 0,
                            child: Icon(_tabs[i].icon),
                          )
                        : Icon(_tabs[i].icon),
                    label: _tabs[i].label,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// En-tête d'accueil : `iconbtn` 44×44 (radius 14, fond `n0`, bordure
/// `n200`, icône `n600` 22px) avec pastille rouge optionnelle (`.dot`).
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.showDot = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: NubiaColors.n0,
              border: Border.all(color: NubiaColors.n200),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(child: Icon(icon, color: NubiaColors.n600, size: 22)),
                if (showDot)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      key: const Key('header_notification_dot'),
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: NubiaColors.dangerFg,
                        shape: BoxShape.circle,
                        border: Border.all(color: NubiaColors.n0, width: 2),
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
