import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bloc/dashboard_bloc.dart';
import 'bloc/dashboard_event.dart';
import 'bloc/dashboard_state.dart';
import 'widgets/dashboard_body.dart';

/// Écran d'accueil patient : vue agrégée dashboard (GET /v1/dashboard).
///
/// Affiche les tuiles cliquables (prochain RDV, documents à signer,
/// paiements, messages, rappels). La navigation vers les écrans dédiés
/// est gérée par [_navigate].
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardBloc, DashboardState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Mon espace'),
          ),
          body: switch (state) {
            DashboardInitial() => const _DashboardLoadTrigger(),
            DashboardLoading() => const Center(
                child: CircularProgressIndicator(),
              ),
            DashboardLoaded(:final summary) => DashboardBody(
                summary: summary,
                onRefresh: () async => context
                    .read<DashboardBloc>()
                    .add(const DashboardLoadRequested()),
                onAppointmentTap: () => _navigate(context, '/appointments'),
                onDocumentsTap: () => _navigate(context, '/documents'),
                onPaymentsTap: () => _navigate(context, '/payments'),
                onMessagesTap: () => _navigate(context, '/messages'),
                onRemindersTap: () => _navigate(context, '/reminders'),
              ),
            DashboardError(:final message) => _DashboardErrorView(
                message: message,
                onRetry: () => context
                    .read<DashboardBloc>()
                    .add(const DashboardLoadRequested()),
              ),
          },
        );
      },
    );
  }

  /// Placeholder de navigation — à remplacer par go_router/Navigator quand
  /// les routes dédiées existent (hors scope de cette issue).
  void _navigate(BuildContext context, String route) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Navigation vers $route')),
    );
  }
}

/// Lance le chargement initial dès que le widget est inséré dans l'arbre.
class _DashboardLoadTrigger extends StatefulWidget {
  const _DashboardLoadTrigger();

  @override
  State<_DashboardLoadTrigger> createState() => _DashboardLoadTriggerState();
}

class _DashboardLoadTriggerState extends State<_DashboardLoadTrigger> {
  @override
  void initState() {
    super.initState();
    context.read<DashboardBloc>().add(const DashboardLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _DashboardErrorView extends StatelessWidget {
  const _DashboardErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}
