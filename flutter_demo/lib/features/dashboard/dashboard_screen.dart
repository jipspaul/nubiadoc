import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../auth/bloc/auth_bloc.dart';
import '../auth/bloc/auth_event.dart';

/// Écran tableau de bord — placeholder post-connexion (US-3.1.1).
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tableau de bord'),
        actions: [
          IconButton(
            key: const Key('dashboard_logout'),
            icon: const Icon(Icons.logout),
            onPressed: () =>
                context.read<AuthBloc>().add(const AuthLogoutRequested()),
          ),
        ],
      ),
      body: Center(
        child: Text(
          'Bienvenue sur Nubia',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
    );
  }
}
