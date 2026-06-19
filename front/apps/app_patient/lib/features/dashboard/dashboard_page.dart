import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../session/auth_cubit.dart';
import '../documents/documents_page.dart';
import '../mes_rdv/mes_rdv_page.dart';
import '../messaging/messaging_page.dart';
import '../home/home_bloc.dart';
import '../home/home_event.dart';
import '../home/home_page.dart';
import '../profile/profile_bloc.dart';
import '../profile/profile_event.dart';
import '../profile/profile_page.dart';

/// Patient home shell: a 5-tab bottom nav (Rechercher / Mes RDV / Messages /
/// Documents / Profil) with stubbed tabs. Proves theming + session + nav.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _index = 0;

  static const _tabs = [
    (label: 'Rechercher', icon: Icons.search),
    (label: 'Mes RDV', icon: Icons.event_outlined),
    (label: 'Messages', icon: Icons.chat_bubble_outline),
    (label: 'Documents', icon: Icons.folder_outlined),
    (label: 'Profil', icon: Icons.person_outline),
  ];

  @override
  Widget build(BuildContext context) {
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(icon: Icon(t.icon), label: t.label),
        ],
      ),
    );
  }
}

