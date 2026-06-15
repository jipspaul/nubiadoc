import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../session/auth_cubit.dart';

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
    final state = context.watch<AuthCubit>().state;
    final name = state is AuthAuthenticated
        ? (state.session.displayName ?? 'Patient')
        : 'Patient';

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
      body: _index == 0
          ? _HomeTab(name: name)
          : Center(
              child: NubiaEmptyState(
                message: '${_tabs[_index].label} — écran à porter depuis app/ '
                    '(référence patient).',
              ),
            ),
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

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Bonjour $name 👋',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        NubiaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StatusPill(label: 'Connecté', variant: StatusPillVariant.success),
              const SizedBox(height: 8),
              Text(
                'Session active via le stack partagé '
                '(nubia_core · nubia_data · GET /v1/me).',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        NubiaButton(
          label: 'Voir la démo A2UI',
          variant: NubiaButtonVariant.secondary,
          onPressed: () => context.push('/a2ui-demo'),
        ),
      ],
    );
  }
}
