import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/app_router.dart';
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

class _HomeContent extends StatefulWidget {
  const _HomeContent({required this.state});

  final HomeLoaded state;

  @override
  State<_HomeContent> createState() => _HomeContentState();
}

/// Pilote l'entrée en cascade des sections de l'accueil : un unique
/// [AnimationController] découpé en [Interval]s décalés de 60 ms par section
/// (en-tête, métriques, à faire, mon suivi / état vide).
class _HomeContentState extends State<_HomeContent>
    with SingleTickerProviderStateMixin {
  static const _staggerMs = 60;
  static const _sectionDurationMs = 320;
  static const _sectionCount = 6;
  static const _totalMs = _sectionDurationMs + (_sectionCount - 1) * _staggerMs;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _totalMs),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Animation<double> _sectionAnimation(int index) {
    final startMs = index * _staggerMs;
    final endMs = startMs + _sectionDurationMs;
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(
        startMs / _totalMs,
        (endMs / _totalMs).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Widget _staggered(BuildContext context, int index, Widget child) {
    if (MediaQuery.of(context).disableAnimations) return child;
    final animation = _sectionAnimation(index);
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: animation.drive(
          Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final authState = context.watch<AuthCubit>().state;
    final name = authState is AuthAuthenticated
        ? (authState.session.displayName ?? 'Patient')
        : 'Patient';

    final s = widget.state.summary;
    final plan = widget.state.treatmentPlan;

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
        _staggered(
          context,
          0,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bonjour $name 👋', style: textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Voici votre espace santé',
                style:
                    textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _staggered(context, 1, _MetricsRow(summary: s)),
        const SizedBox(height: 28),
        if (hasShortcuts)
          _staggered(
            context,
            2,
            _TodoSection(summary: s, hasFinancial: hasFinancial),
          ),
        if (hasShortcuts) const SizedBox(height: 28),
        _staggered(context, 3, const _QuickAccessGrid()),
        if (plan != null) ...[
          const SizedBox(height: 28),
          _staggered(
            context,
            4,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionLabel(label: 'Mon suivi'),
                const SizedBox(height: 12),
                _TreatmentProgressCard(plan: plan),
              ],
            ),
          ),
        ],
        if (allClear)
          _staggered(
            context,
            5,
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: NubiaEmptyState(
                key: Key('home_empty'),
                icon: Icons.check_circle_outline,
                title: 'Tout est à jour',
                subtitle: 'Aucune action en attente.',
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Trois tuiles de métriques : à signer / à régler / prochain RDV.
class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _PressableScale(
              pressable: s.documentsToSign > 0,
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
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _PressableScale(
              pressable: s.pendingPaymentsCents > 0,
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
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _PressableScale(
              pressable: true,
              child: MetricTile(
                key: const Key('card_appointments'),
                icon: Icons.event_outlined,
                value: '${s.upcomingAppointments}',
                label: 'Prochain RDV',
                onTap: () => context.push('/appointments'),
              ),
            ),
          ),
        ],
      ),
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

/// Section « À faire » : devis à signer/régler et messages non lus.
class _TodoSection extends StatelessWidget {
  const _TodoSection({required this.summary, required this.hasFinancial});

  final DashboardSummary summary;
  final bool hasFinancial;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(label: 'À faire'),
        const SizedBox(height: 12),
        if (hasFinancial) ...[
          _PressableScale(
            pressable: true,
            child: _ShortcutCard(
              key: const Key('card_devis'),
              icon: Icons.description_outlined,
              title: 'Devis à signer / à régler',
              subtitle: 'Consultez, signez et réglez vos devis.',
              count: s.documentsToSign > 0 ? s.documentsToSign : null,
              onTap: () => context.push('/financial'),
            ),
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
    );
  }
}

// ---------------------------------------------------------------------------

/// Section « Accès rapide » : grille 2×2 de raccourcis vers les wedges
/// aujourd'hui enterrés dans le routeur (ordonnances, documents, pharmacie,
/// proches — maquette `patient-accueil.png`, note #3). Les sous-titres
/// d'état sont statiques : ils ne sont pas dans [DashboardSummary], leur
/// câblage sur les données réelles est un ticket data séparé (#5201).
class _QuickAccessGrid extends StatelessWidget {
  const _QuickAccessGrid();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(label: 'Accès rapide'),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _QuickAccessTile(
                  key: const Key('quick_access_prescriptions'),
                  icon: Icons.medication,
                  iconBg: tokens.primarySubtleBg,
                  iconColor: cs.primary,
                  title: 'Mes ordonnances',
                  subtitle: '1 active',
                  // Pas de route ordonnances dédiée aujourd'hui (#5201) —
                  // cible à confirmer avec le PO, on n'invente pas d'écran.
                  onTap: null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickAccessTile(
                  key: const Key('quick_access_documents'),
                  icon: Icons.folder_open,
                  iconBg: tokens.infoBg,
                  iconColor: tokens.infoFg,
                  title: 'Mes documents',
                  subtitle: '12 fichiers',
                  onTap: () => context.push(AppRouter.documents),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _QuickAccessTile(
                  key: const Key('quick_access_pharmacy'),
                  icon: Icons.local_pharmacy,
                  iconBg: tokens.primarySubtleBg,
                  iconColor: cs.primary,
                  title: 'Ma pharmacie',
                  subtitle: 'Pharmacie du Théâtre',
                  onTap: () => context.push('/pharmacy'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickAccessTile(
                  key: const Key('quick_access_dependents'),
                  icon: Icons.group,
                  iconBg: tokens.primarySubtleBg,
                  iconColor: cs.primary,
                  title: 'Mes proches',
                  subtitle: '2 comptes liés',
                  onTap: () => context.push(AppRouter.profileDependents),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Tuile « Accès rapide » : pastille icône 38×38 (radius 11) en haut, titre
/// + sous-titre d'état en bas. `min-height` 96, fond `n0`, bordure `n200`,
/// radius 18 (maquette `patient-accueil.png`, note #3). Aucune logique
/// réseau ici : [onTap] est fourni par l'appelant.
class _QuickAccessTile extends StatelessWidget {
  const _QuickAccessTile({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 96),
      child: Material(
        color: NubiaColors.n0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: NubiaColors.n200),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 19, color: iconColor),
                ),
                const SizedBox(height: 10),
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
        ),
      ),
    );
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

/// Carte « Plan de traitement » de la section « Mon suivi » (#5202) : icône
/// accent sable, compteur d'étapes, barre segmentée et libellé de la
/// prochaine étape. Seul endroit de l'accueil où l'accent sable
/// ([NubiaTokens.accent]) est autorisé — règle design #4 de la maquette
/// `patient-accueil.png`. Un tap ouvre la liste des plans de traitement.
///
/// Les étapes affichées viennent de [PatientTreatmentPlan.currentStep] /
/// [PatientTreatmentPlan.stepCount], jamais codées en dur.
class _TreatmentProgressCard extends StatelessWidget {
  const _TreatmentProgressCard({required this.plan});

  final PatientTreatmentPlan plan;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final total = plan.stepCount!;
    final completed = ((plan.currentStep ?? total) - 1).clamp(0, total).toInt();

    return Material(
      key: const Key('treatment_progress_card'),
      color: NubiaColors.n0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: NubiaColors.n200),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRouter.treatmentPlans),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.workspace_premium, size: 20, color: tokens.accent),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Plan de traitement',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '$completed / $total étapes',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: NubiaColors.n500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _TreatmentProgressTrack(total: total, completed: completed),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  style:
                      const TextStyle(fontSize: 12.5, color: NubiaColors.n600),
                  children: [
                    const TextSpan(text: 'Prochaine étape · '),
                    TextSpan(
                      text: plan.currentPhaseTitle!,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: NubiaColors.n900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barre `track` segmentée : un segment par étape, plein `brand/600` pour
/// les étapes complétées, `n200` pour les restantes (#5202).
class _TreatmentProgressTrack extends StatelessWidget {
  const _TreatmentProgressTrack({required this.total, required this.completed});

  final int total;
  final int completed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: NubiaColors.n100,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color:
                      i < completed ? NubiaColors.brand600 : NubiaColors.n200,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ],
        ],
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

// ---------------------------------------------------------------------------

/// Retour tactile discret : réduit [child] à 0.97 pendant l'appui.
///
/// N'utilise pas [GestureDetector] pour ne pas entrer en concurrence avec le
/// geste de tap propre à [child] (ex. l'[InkWell] interne d'un [MetricTile])
/// dans l'arène de gestes ; [Listener] observe le pointeur sans l'intercepter.
class _PressableScale extends StatefulWidget {
  const _PressableScale({required this.child, this.pressable = true});

  final Widget child;
  final bool pressable;

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: widget.pressable ? (_) => _setPressed(true) : null,
      onPointerUp: widget.pressable ? (_) => _setPressed(false) : null,
      onPointerCancel: widget.pressable ? (_) => _setPressed(false) : null,
      child: AnimatedScale(
        scale: _pressed && widget.pressable ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
