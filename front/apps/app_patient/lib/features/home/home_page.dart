import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/app_router.dart';
import '../../session/auth_cubit.dart';
import 'home_bloc.dart';
import 'home_event.dart';
import 'home_state.dart';
import 'widgets/hero_appointment_card.dart';

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

/// Garantit que les symboles `intl` (dont `fr_FR`) sont chargés avant le
/// premier `DateFormat` — la charge est synchrone (données CLDR embarquées),
/// donc sûre à appeler depuis `build`. Idempotent : ne refait le travail
/// qu'une fois par process.
bool _dateFormattingInitialized = false;

/// Date du jour en français, ex. « Mardi 11 août » (sans année, 1re lettre
/// du jour capitalisée — sous-titre de l'en-tête, maquette
/// `patient-accueil.png`).
String _todayLabel() {
  if (!_dateFormattingInitialized) {
    initializeDateFormatting();
    _dateFormattingInitialized = true;
  }
  final formatted = DateFormat('EEEE d MMMM', 'fr_FR').format(DateTime.now());
  return formatted[0].toUpperCase() + formatted.substring(1);
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
/// (en-tête, héros RDV, métriques, à faire, mon suivi / état vide).
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
    final sessionDisplayName =
        authState is AuthAuthenticated ? authState.session.displayName : null;
    final name = (sessionDisplayName == null || sessionDisplayName.trim().isEmpty)
        ? 'Patient'
        : sessionDisplayName;

    final s = widget.state.summary;
    final plan = widget.state.treatmentPlan;

    // Devis à signer/régler : point d'entrée visible vers le wedge financier
    // (l'écran devis n'a pas d'onglet dédié dans la barre du bas).
    final bool hasFinancial =
        s.documentsToSign > 0 || s.pendingPaymentsCents > 0;
    final bool hasShortcuts = s.unreadMessages > 0 || hasFinancial;
    final nextAppointment = widget.state.nextAppointment;
    // Vrai quand la carte héros affiche réellement un contenu (détail du
    // prochain RDV ou CTA de prise de rendez-vous) — faux quand un RDV est
    // prévu mais que son détail n'a pas pu être chargé (carte masquée).
    final bool heroVisible =
        nextAppointment != null || s.upcomingAppointments == 0;
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
              Text('Bonjour $name', style: textTheme.displayLarge),
              const SizedBox(height: 4),
              Text(
                _todayLabel(),
                style:
                    textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _staggered(
          context,
          1,
          HeroAppointmentCard(
            upcomingAppointments: s.upcomingAppointments,
            nextAppointment: nextAppointment,
          ),
        ),
        if (heroVisible) const SizedBox(height: 20),
        if (hasShortcuts)
          _staggered(
            context,
            2,
            _TodoSection(summary: s),
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

/// Section « À faire » : liste d'actions (devis à signer, reste à charge,
/// messages non lus) en lignes séparées — chacune porte un badge ou un
/// montant + chevron vers sa cible (maquette `patient-accueil.png`, note #2).
/// Le reste à charge s'affiche en euros formatés (`danger/fg`), jamais en
/// chiffre nu.
class _TodoSection extends StatelessWidget {
  const _TodoSection({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    final rows = <Widget>[
      if (s.documentsToSign > 0)
        ListRow(
          key: const Key('card_devis'),
          leading: _TodoLeadingIcon(
            icon: Icons.draw_outlined,
            background: tokens.warningBg,
            color: tokens.warningFg,
          ),
          title: 'Devis à signer',
          subtitle: 'Consultez et signez vos devis en attente.',
          showDivider: false,
          onTap: () => context.push('/financial'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NubiaBadge.count(count: s.documentsToSign),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      if (s.pendingPaymentsCents > 0)
        ListRow(
          key: const Key('card_reste_a_charge'),
          leading: _TodoLeadingIcon(
            icon: Icons.receipt_long_outlined,
            background: tokens.dangerBg,
            color: tokens.dangerFg,
          ),
          title: 'Reste à charge',
          subtitle: 'Factures en attente de règlement.',
          showDivider: false,
          onTap: () => context.push('/financial'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                NubiaMoney.formatCents(s.pendingPaymentsCents),
                style: textTheme.titleSmall?.copyWith(
                  color: tokens.dangerFg,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      if (s.unreadMessages > 0)
        ListRow(
          key: const Key('card_messages'),
          leading: _TodoLeadingIcon(
            icon: Icons.chat_bubble_outline,
            background: tokens.primarySubtleBg,
            color: cs.primary,
          ),
          title: s.unreadMessages > 1
              ? 'Messages du cabinet'
              : 'Message du cabinet',
          subtitle: 'Vous avez du courrier de vos praticiens.',
          showDivider: false,
          onTap: () => context.push(AppRouter.messaging),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NubiaBadge.count(count: s.unreadMessages),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'À faire', count: rows.length),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: NubiaColors.n0,
            border: Border.all(color: NubiaColors.n200),
            borderRadius: BorderRadius.circular(18),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i < rows.length - 1)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: NubiaColors.n100,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Pastille icône 40×40 (radius 10) d'une ligne « À faire ».
class _TodoLeadingIcon extends StatelessWidget {
  const _TodoLeadingIcon({
    required this.icon,
    required this.background,
    required this.color,
  });

  final IconData icon;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

// ---------------------------------------------------------------------------

/// Section « Accès rapide » : grille 2×2 de raccourcis vers les wedges
/// aujourd'hui enterrés dans le routeur (ordonnances, documents, pharmacie,
/// proches — maquette `patient-accueil.png`, note #3). Les sous-titres
/// d'état ne sont pas dans [DashboardSummary] ; leur câblage sur les
/// données réelles est un ticket data séparé (#5201). En attendant, on
/// n'affiche PAS les valeurs d'exemple de la maquette (elles mentent —
/// #6215) : le sous-titre est omis quand on n'a pas la vraie donnée.
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
                  subtitle: null,
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
                  subtitle: null,
                  // #6236 : `go()`, pas `push()` (cf. hero_appointment_card.dart).
                  onTap: () => context.go(AppRouter.documents),
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
                  subtitle: null,
                  // #6236 : `go()`, pas `push()` (cf. hero_appointment_card.dart).
                  onTap: () => context.go('/pharmacy'),
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
                  subtitle: null,
                  // #6236 : `go()`, pas `push()` (cf. hero_appointment_card.dart).
                  onTap: () => context.go(AppRouter.profileDependents),
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
                  key: const Key('quick_access_home_care'),
                  icon: Icons.medical_services_outlined,
                  iconBg: tokens.primarySubtleBg,
                  iconColor: cs.primary,
                  title: 'Soins à domicile',
                  subtitle: 'Demander une infirmière',
                  onTap: () => context.push(AppRouter.homeCare),
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
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String? subtitle;
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
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Libellé de section, avec une pastille compteur optionnelle (fond `n200`,
/// texte `n600` — maquette `patient-accueil.png`, note #2).
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, this.count});

  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: textTheme.titleSmall?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: NubiaColors.n200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: textTheme.labelSmall?.copyWith(
                color: NubiaColors.n600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
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
    // `currentStep ?? 1` : sans info serveur, on suppose qu'on est à la
    // première étape plutôt que la dernière (#6233 — l'ancien `?? total`
    // affichait « tout est fait » alors qu'on ne sait rien).
    final completed = ((plan.currentStep ?? 1) - 1).clamp(0, total).toInt();

    return Material(
      key: const Key('treatment_progress_card'),
      color: NubiaColors.n0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: NubiaColors.n200),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // #6236 : `go()`, pas `push()` (cf. hero_appointment_card.dart).
        onTap: () => context.go(AppRouter.treatmentPlans),
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

