import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../agenda/agenda_bloc.dart';
import '../agenda/agenda_event.dart';
import 'dashboard_bloc.dart';
import 'dashboard_event.dart';
import 'dashboard_state.dart';
import 'next_patient_hero.dart';
import 'pending_actions_card.dart';
import 'today_notes_bloc.dart';
import 'today_notes_card.dart';
import 'today_schedule_card.dart';
import 'week_summary_card.dart';

/// Contenu de la branche « Tableau de bord » du `StatefulShellRoute`
/// (`app_router.dart`) — construit son propre `DashboardBloc`,
/// indépendamment de `PracticienShell` qui l'héberge (#6286, même approche
/// que `DashboardBody`/`SecretariatShell` côté app_secretariat).
class DashboardBody extends StatelessWidget {
  const DashboardBody({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<DashboardBloc>()
        ..add(const DashboardLoadRequested()),
      child: const _DashboardContent(),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardBloc, DashboardState>(
      builder: (context, state) {
        return switch (state) {
          DashboardInitial() ||
          DashboardLoading() =>
            const _DashboardLoadingView(key: Key('dashboard_loading')),
          DashboardError(:final message) => NubiaErrorWidget(
              key: const Key('dashboard_error'),
              message: message,
              onRetry: () => context
                  .read<DashboardBloc>()
                  .add(const DashboardLoadRequested()),
            ),
          DashboardLoaded(:final summary) => _DashboardLoadedView(
              summary: summary,
            ),
        };
      },
    );
  }
}

class _DashboardLoadedView extends StatelessWidget {
  const _DashboardLoadedView({required this.summary});

  final ProDashboardSummary summary;

  // Seuil au-delà duquel la colonne droite (430 px fixe) + la gouttière
  // (16 px) laissent assez de place à gauche pour rester lisible.
  static const _wideBreakpoint = 1100.0;
  static const _rightColumnWidth = 430.0;
  static const _gutter = 16.0;

  @override
  Widget build(BuildContext context) {
    final todayScheduleCard = BlocProvider(
      create: (_) {
        final now = DateTime.now();
        final weekStart = DateTime(
          now.year,
          now.month,
          now.day - (now.weekday - 1),
        );
        return GetIt.instance<AgendaBloc>()
          ..add(AgendaLoadRequested(weekStart: weekStart));
      },
      child: TodayScheduleCard(summary: summary),
    );
    final pendingActionsCard = PendingActionsCard(summary: summary);
    final notesCard = BlocProvider(
      create: (_) => GetIt.instance<TodayNotesBloc>()
        ..add(const TodayNotesLoadRequested()),
      child: const TodayNotesCard(),
    );
    final weekSummaryCard = WeekSummaryCard(summary: summary);

    return SingleChildScrollView(
      key: const Key('dashboard_loaded'),
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= _wideBreakpoint) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _DashboardHeader(),
                      const SizedBox(height: 16),
                      NextPatientHero(summary: summary),
                      const SizedBox(height: 16),
                      todayScheduleCard,
                    ],
                  ),
                ),
                const SizedBox(width: _gutter),
                SizedBox(
                  width: _rightColumnWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      pendingActionsCard,
                      const SizedBox(height: 16),
                      notesCard,
                      const SizedBox(height: 16),
                      weekSummaryCard,
                    ],
                  ),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _DashboardHeader(),
              const SizedBox(height: 16),
              NextPatientHero(summary: summary),
              const SizedBox(height: 16),
              todayScheduleCard,
              const SizedBox(height: 24),
              pendingActionsCard,
              const SizedBox(height: 16),
              notesCard,
              const SizedBox(height: 16),
              weekSummaryCard,
            ],
          );
        },
      ),
    );
  }
}

/// Bandeau de titre du tableau de bord (hiérarchie `h2` + sous-titre `caption`).
class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Ma journée',
          style: textTheme.headlineSmall?.copyWith(color: cs.onSurface),
        ),
        const SizedBox(height: 4),
        Text(
          'Aperçu de votre activité clinique du jour',
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Squelette de chargement : quatre tuiles de métrique animées.
class _DashboardLoadingView extends StatelessWidget {
  const _DashboardLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const NubiaSkeletonLoader(width: 160, height: 28),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (int i = 0; i < 4; i++)
                const NubiaSkeletonLoader(
                  width: 180,
                  height: 108,
                  borderRadius: 12,
                ),
            ],
          ),
          const SizedBox(height: 24),
          const NubiaSkeletonLoader(height: 180, borderRadius: 12),
        ],
      ),
    );
  }
}
