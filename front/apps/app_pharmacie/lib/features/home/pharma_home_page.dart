import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' hide ProConfig;
import 'package:nubia_core/nubia_core.dart';

import '../../pharma_config.dart';
import '../../session/pharma_auth_cubit.dart';

/// Entry point for the authenticated pharmacie home. Delegates layout to
/// [ProShell] (NavigationRail on desktop, Drawer on mobile).
///
/// Squelette (lot F3) : chaque destination affiche le placeholder par défaut
/// du shell — les écrans métier arrivent avec les lots F4–F6.
class PharmaHomePage extends StatelessWidget {
  const PharmaHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = switch (context.watch<PharmaAuthCubit>().state) {
      AuthAuthenticated(:final session) => session,
      _ => const AuthSession(
          kind: UserKind.pro,
          userId: 'me',
          role: PharmaConfig.role,
        ),
    };

    return ProShell(
      config: PharmaConfig.shellConfig,
      session: session,
      onSignOut: () => context.read<PharmaAuthCubit>().signOut(),
    );
  }
}
