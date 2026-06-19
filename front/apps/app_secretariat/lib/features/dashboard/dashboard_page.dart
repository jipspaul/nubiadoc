import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' hide ProConfig;
import 'package:nubia_core/nubia_core.dart';

import '../../pro_config.dart';
import '../../session/pro_auth_cubit.dart';

/// Entry point for the authenticated secrétariat home. Delegates layout to
/// [ProShell] (NavigationRail on desktop, Drawer on mobile). Clinical
/// filtering is enforced inside [ProShell] via [AuthSession.canAccessClinical];
/// all destinations here are administrative-only so the filter is redundant
/// but provides defense-in-depth.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = switch (context.watch<ProAuthCubit>().state) {
      AuthAuthenticated(:final session) => session,
      _ => const AuthSession(
          kind: UserKind.pro,
          userId: 'me',
          role: ProConfig.role,
        ),
    };

    return ProShell(
      config: ProConfig.shellConfig,
      session: session,
      trailingActions: [
        IconButton(
          tooltip: 'Démo A2UI',
          icon: const Icon(Icons.auto_awesome_outlined),
          onPressed: () => context.push('/a2ui-demo'),
        ),
      ],
      onSignOut: () => context.read<ProAuthCubit>().signOut(),
    );
  }
}
