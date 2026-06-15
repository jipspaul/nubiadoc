import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../pro_config.dart';
import '../../session/pro_auth_cubit.dart';

/// Pro home shell: a side NavigationRail (desktop/tablet-first) with role-gated
/// destinations. Clinical entries are filtered out for non-clinical roles —
/// the structural guarantee for the secretariat app's zero-clinical access.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final session = switch (context.watch<ProAuthCubit>().state) {
      AuthAuthenticated(:final session) => session,
      _ => const AuthSession(kind: UserKind.pro, userId: 'me', role: ProConfig.role),
    };

    // Defense in depth: even though each app ships only its own nav, filter
    // clinical destinations by the live session capability.
    final nav = ProConfig.nav
        .where((d) => !d.clinical || session.canAccessClinical)
        .toList();
    final current = nav[_index.clamp(0, nav.length - 1)];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index.clamp(0, nav.length - 1),
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: FlutterLogo(),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Démo A2UI',
                        icon: const Icon(Icons.auto_awesome_outlined),
                        onPressed: () => context.push('/a2ui-demo'),
                      ),
                      IconButton(
                        tooltip: 'Se déconnecter',
                        icon: const Icon(Icons.logout),
                        onPressed: () => context.read<ProAuthCubit>().signOut(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            destinations: [
              for (final d in nav)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Scaffold(
              appBar: NubiaAppBar(title: current.label, centerTitle: false),
              body: Center(
                child: NubiaEmptyState(
                  message: '${current.label} — ${ProConfig.spaceLabel}. '
                      'Écran à implémenter sur le stack partagé.',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
