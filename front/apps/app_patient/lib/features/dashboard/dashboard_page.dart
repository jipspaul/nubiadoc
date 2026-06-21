import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../session/auth_cubit.dart';
import '../documents/documents_page.dart';
import '../mes_rdv/mes_rdv_page.dart';
import '../messaging/messaging_bloc.dart';
import '../messaging/messaging_event.dart';
import '../messaging/messaging_page.dart';
import '../messaging/messaging_state.dart';
import '../home/home_bloc.dart';
import '../home/home_event.dart';
import '../home/home_page.dart';
import '../profile/profile_bloc.dart';
import '../profile/profile_event.dart';
import '../profile/profile_page.dart';
import 'dashboard_bloc.dart';
import 'dashboard_event.dart';
import 'dashboard_state.dart';

/// Patient home shell: a 5-tab bottom nav (Rechercher / Mes RDV / Messages /
/// Documents / Profil) with stubbed tabs. Proves theming + session + nav.
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
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => GetIt.instance<DashboardBloc>()
            ..add(const DashboardLoadRequested()),
        ),
        BlocProvider.value(value: _messagingBloc),
      ],
      child: BlocBuilder<DashboardBloc, DashboardState>(
        builder: (context, state) {
          if (state is DashboardError) {
            return Scaffold(
              body: NubiaErrorWidget(
                key: const Key('dashboard_error'),
                message: state.message,
                onRetry: () => context
                    .read<DashboardBloc>()
                    .add(const DashboardLoadRequested()),
              ),
            );
          }
          return Scaffold(
            appBar: NubiaAppBar(
              title: _tabs[_index].label,
              actions: [
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
                  create: (_) => GetIt.instance<HomeBloc>()
                    ..add(const HomeLoadRequested()),
                  child: const HomePage(),
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
            bottomNavigationBar:
                BlocSelector<MessagingBloc, MessagingState, int>(
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
          );
        },
      ),
    );
  }
}
