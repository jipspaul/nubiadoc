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
          return const Center(child: CircularProgressIndicator());
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
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final authState = context.watch<AuthCubit>().state;
    final name = authState is AuthAuthenticated
        ? (authState.session.displayName ?? 'Patient')
        : 'Patient';

    final s = state.summary;

    // Devis à signer/régler : point d'entrée visible vers le wedge financier
    // (l'écran devis n'a pas d'onglet dédié dans la barre du bas).
    final bool hasFinancial =
        s.documentsToSign > 0 || s.pendingPaymentsCents > 0;
    final bool hasShortcuts = s.unreadMessages > 0 || hasFinancial;
    final bool allClear = s.upcomingAppointments == 0 &&
        s.documentsToSign == 0 &&
        s.unreadMessages == 0 &&
        s.pendingPaymentsCents == 0;

    return ListView(
      key: const Key('home_content'),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        Text(
          'Bonjour $name 👋',
          style: textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Voici votre espace santé',
          style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        // Trois tuiles de métriques : à signer / à régler / prochain RDV.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: MetricTile(
                  key: const Key('card_documents'),
                  icon: Icons.edit_document,
                  value: '${s.documentsToSign}',
                  label: 'À signer',
                  variant: s.documentsToSign > 0
                      ? MetricTileVariant.warning
                      : MetricTileVariant.neutral,
                  // Les devis à signer vivent dans le wedge financier.
                  onTap: s.documentsToSign > 0
                      ? () => context.push('/financial')
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricTile(
                  key: const Key('card_financial'),
                  icon: Icons.receipt_long_outlined,
                  value: _formatEuros(s.pendingPaymentsCents),
                  label: 'À régler',
                  variant: s.pendingPaymentsCents > 0
                      ? MetricTileVariant.danger
                      : MetricTileVariant.neutral,
                  onTap: s.pendingPaymentsCents > 0
                      ? () => context.push('/financial')
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricTile(
                  key: const Key('card_appointments'),
                  icon: Icons.event_outlined,
                  value: '${s.upcomingAppointments}',
                  label: 'Prochain RDV',
                  onTap: () => context.push('/appointments'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        if (hasShortcuts) ...[
          const _SectionLabel(label: 'À faire'),
          const SizedBox(height: 12),
          if (hasFinancial) ...[
            _ShortcutCard(
              key: const Key('card_devis'),
              icon: Icons.description_outlined,
              title: 'Devis à signer / à régler',
              subtitle: 'Consultez, signez et réglez vos devis.',
              count: s.documentsToSign > 0 ? s.documentsToSign : null,
              onTap: () => context.push('/financial'),
            ),
            const SizedBox(height: 12),
          ],
          if (s.unreadMessages > 0) ...[
            _ShortcutCard(
              key: const Key('card_messages'),
              icon: Icons.chat_bubble_outline,
              title: 'Messages non lus',
              subtitle: 'Vous avez du courrier de vos praticiens.',
              count: s.unreadMessages,
            ),
            const SizedBox(height: 12),
          ],
        ],
        if (allClear)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: NubiaEmptyState(
              key: Key('home_empty'),
              icon: Icons.check_circle_outline,
              title: 'Tout est à jour',
              subtitle: 'Aucune action en attente.',
            ),
          ),
      ],
    );
  }

  static String _formatEuros(int cents) {
    final value = cents / 100;
    final text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
    return '${text.replaceAll('.', ',')} €';
  }
}

// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Carte de raccourci « À faire » : pastille icône + titre/sous-titre + badge
/// compteur. Informative — les tuiles au-dessus portent les actions
/// principales de navigation.
class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.count,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int? count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return NubiaCard(
      state:
          onTap != null ? NubiaCardState.interactive : NubiaCardState.static_,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tokens.primarySubtleBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (count != null)
            NubiaBadge.count(count: count!)
          else if (onTap != null)
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}
