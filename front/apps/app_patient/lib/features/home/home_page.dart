import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../session/auth_cubit.dart';
import 'home_bloc.dart';
import 'home_event.dart';
import 'home_state.dart';

/// Patient home tab — dashboard branché sur [GetDashboardSummaryUseCase].
///
/// Doit être placé dans un [BlocProvider<HomeBloc>] avec un appel initial
/// [HomeLoadRequested] (voir [DashboardPage]).
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeBloc, HomeState>(
      builder: (context, state) {
        if (state is HomeInitial || state is HomeLoading) {
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 4,
            itemBuilder: (_, __) => const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: NubiaSkeletonLoader(height: 72),
            ),
          );
        }
        if (state is HomeError) {
          return NubiaErrorWidget(
            message: state.message,
            onRetry: () =>
                context.read<HomeBloc>().add(const HomeLoadRequested()),
          );
        }
        if (state is HomeLoaded) {
          return _HomeContent(state: state);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _HomeContent extends StatelessWidget {
  const _HomeContent({required this.state});

  final HomeLoaded state;

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final name = authState is AuthAuthenticated
        ? (authState.session.displayName ?? 'Patient')
        : 'Patient';

    final s = state.summary;

    return ListView(
      key: const Key('home_content'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Bonjour $name 👋',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        if (s.upcomingAppointments > 0)
          _SummaryCard(
            key: const Key('card_appointments'),
            icon: Icons.event_outlined,
            label: 'Prochain rendez-vous',
            value: '${s.upcomingAppointments} à venir',
            onTap: () => context.push('/appointments'),
          ),
        if (s.documentsToSign > 0)
          _SummaryCard(
            key: const Key('card_documents'),
            icon: Icons.edit_document,
            label: 'Documents à signer',
            value: '${s.documentsToSign}',
          ),
        if (s.unreadMessages > 0)
          _SummaryCard(
            key: const Key('card_messages'),
            icon: Icons.chat_bubble_outline,
            label: 'Messages non lus',
            value: '${s.unreadMessages}',
          ),
        if (s.pendingQuestionnaires > 0)
          _SummaryCard(
            key: const Key('card_questionnaires'),
            icon: Icons.assignment_outlined,
            label: 'Questionnaires en attente',
            value: '${s.pendingQuestionnaires}',
          ),
        if (s.pendingPaymentsCents > 0)
          _SummaryCard(
            key: const Key('card_financial'),
            icon: Icons.receipt_long_outlined,
            label: 'Devis en attente',
            value: '${(s.pendingPaymentsCents / 100).toStringAsFixed(2).replaceAll('.', ',')} €',
            onTap: () => context.push('/financial'),
          ),
        if (s.upcomingAppointments == 0 &&
            s.documentsToSign == 0 &&
            s.unreadMessages == 0 &&
            s.pendingQuestionnaires == 0 &&
            s.pendingPaymentsCents == 0)
          const NubiaEmptyState(
            key: Key('home_empty'),
            icon: Icons.check_circle_outline,
            title: 'Tout est à jour',
            subtitle: 'Aucune action en attente.',
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NubiaCard(
        child: ListTile(
          leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
          title: Text(label),
          trailing: Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
