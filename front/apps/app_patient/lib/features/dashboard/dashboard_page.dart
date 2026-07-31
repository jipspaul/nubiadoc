import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../session/auth_cubit.dart';
import '../appointments/appointments_bloc.dart';
import '../appointments/appointments_page.dart';
import '../documents/documents_page.dart';
import '../mes_rdv/mes_rdv_page.dart';
import '../messaging/messaging_bloc.dart';
import '../messaging/messaging_event.dart';
import '../messaging/messaging_page.dart';
import '../messaging/messaging_state.dart';
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
  }

  @override
  void dispose() {
    _messagingBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _messagingBloc,
      child: Scaffold(
        appBar: NubiaAppBar(
          title: _tabs[_index].label,
          actions: [
            if (kDebugMode)
              IconButton(
                icon: const Icon(Icons.auto_awesome_outlined),
                tooltip: 'Démo A2UI',
                onPressed: () => context.push('/a2ui-demo'),
              ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Se déconnecter',
              onPressed: () => context.read<AuthCubit>().signOut(),
            ),
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
