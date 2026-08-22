import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'mes_rdv_bloc.dart';
import 'mes_rdv_event.dart';
import 'mes_rdv_state.dart';

/// Onglet "Mes RDV" — liste upcoming/historique + cancel/checkin.
class MesRdvPage extends StatelessWidget {
  const MesRdvPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          GetIt.instance<MesRdvBloc>()..add(const MesRdvLoadRequested()),
      child: const _MesRdvBody(),
    );
  }
}

// ---------------------------------------------------------------------------

class _MesRdvBody extends StatelessWidget {
  const _MesRdvBody();

  @override
  Widget build(BuildContext context) {
    return BlocListener<MesRdvBloc, MesRdvState>(
      listenWhen: (_, current) =>
          current is MesRdvLoaded && current.actionError != null,
      listener: (context, state) {
        if (state is MesRdvLoaded && state.actionError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.actionError!)),
          );
        }
      },
      child: BlocBuilder<MesRdvBloc, MesRdvState>(
        builder: (context, state) {
          if (state is MesRdvInitial || state is MesRdvLoading) {
            return const _MesRdvLoadingSkeleton();
          }
          if (state is MesRdvError) {
            return NubiaErrorWidget(
              key: const Key('mes_rdv_error'),
              message: state.message,
              onRetry: () =>
                  context.read<MesRdvBloc>().add(const MesRdvLoadRequested()),
            );
          }
          if (state is MesRdvLoaded) {
            return _LoadedView(state: state);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Squelette de chargement : reprend le rythme des cartes réelles
/// (même padding de liste, silhouette rail + titre/sous-titre + action).
class _MesRdvLoadingSkeleton extends StatelessWidget {
  const _MesRdvLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const Key('mes_rdv_loading'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: 3,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: _MesRdvCardSkeleton(),
      ),
    );
  }
}

class _MesRdvCardSkeleton extends StatelessWidget {
  const _MesRdvCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const NubiaSkeletonLoader(
                  width: 52, height: 52, borderRadius: 999),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const NubiaSkeletonLoader(width: 140, height: 14),
                    const SizedBox(height: 8),
                    const NubiaSkeletonLoader(width: 180, height: 12),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const NubiaSkeletonLoader(width: 160, height: 12),
          const SizedBox(height: 12),
          Row(
            children: [
              const NubiaSkeletonLoader(width: 96, height: 32),
              const SizedBox(width: 8),
              const NubiaSkeletonLoader(width: 96, height: 32),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _LoadedView extends StatefulWidget {
  const _LoadedView({required this.state});
  final MesRdvLoaded state;

  @override
  State<_LoadedView> createState() => _LoadedViewState();
}

class _LoadedViewState extends State<_LoadedView> {
  // #3801 : « À venir » et « Historique » veulent des ordres par défaut
  // opposés (le prochain RDV en tête vs le plus récent passé en tête) — un
  // seul état de tri partagé appliquait l'ordre pensé pour l'historique
  // (DESC) à l'onglet à venir, reléguant le RDV imminent en bas de liste.
  bool _upcomingSortAsc = true;
  bool _historySortAsc = false;
  int _selectedIndex = 0;

  bool get _currentSortAsc =>
      _selectedIndex == 0 ? _upcomingSortAsc : _historySortAsc;

  void _toggleSort() => setState(() {
        if (_selectedIndex == 0) {
          _upcomingSortAsc = !_upcomingSortAsc;
        } else {
          _historySortAsc = !_historySortAsc;
        }
      });

  @override
  Widget build(BuildContext context) {
    int compareUpcoming(Appointment a, Appointment b) => _upcomingSortAsc
        ? a.startsAt.compareTo(b.startsAt)
        : b.startsAt.compareTo(a.startsAt);
    int compareHistory(Appointment a, Appointment b) => _historySortAsc
        ? a.startsAt.compareTo(b.startsAt)
        : b.startsAt.compareTo(a.startsAt);

    final upcoming = [...widget.state.upcoming]..sort(compareUpcoming);
    final history = [...widget.state.history]..sort(compareHistory);

    return Column(
      children: [
        if (widget.state.actionInProgress)
          const LinearProgressIndicator(key: Key('mes_rdv_action_progress')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: SegmentedControl(
                  key: const Key('mes_rdv_segments'),
                  segments: const ['À venir', 'Historique'],
                  selectedIndex: _selectedIndex,
                  onChanged: (i) => setState(() => _selectedIndex = i),
                ),
              ),
              IconButton(
                key: const Key('sort_button'),
                icon: const Icon(Icons.sort),
                tooltip: _selectedIndex == 0
                    ? (_currentSortAsc
                        ? 'Plus lointain d\'abord'
                        : 'Plus proche d\'abord')
                    : (_currentSortAsc
                        ? 'Plus récent d\'abord'
                        : 'Plus ancien d\'abord'),
                onPressed: _toggleSort,
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _selectedIndex,
            sizing: StackFit.expand,
            children: [
              _AppointmentList(
                key: const Key('upcoming_list'),
                appointments: upcoming,
                emptyLabel: 'Aucun rendez-vous à venir',
                isUpcoming: true,
              ),
              _AppointmentList(
                key: const Key('history_list'),
                appointments: history,
                emptyLabel: 'Aucun historique',
                isUpcoming: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _AppointmentList extends StatelessWidget {
  const _AppointmentList({
    super.key,
    required this.appointments,
    required this.emptyLabel,
    required this.isUpcoming,
  });

  final List<Appointment> appointments;
  final String emptyLabel;
  final bool isUpcoming;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        final bloc = context.read<MesRdvBloc>();
        bloc.add(const MesRdvLoadRequested());
        await bloc.stream.firstWhere(
          (s) => s is MesRdvLoaded || s is MesRdvError,
          orElse: () => const MesRdvLoading(),
        );
      },
      child: appointments.isEmpty
          ? LayoutBuilder(
              builder: (_, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: NubiaEmptyState(
                    key: Key('empty_${isUpcoming ? 'upcoming' : 'history'}'),
                    icon: Icons.calendar_today_outlined,
                    title: emptyLabel,
                    action: isUpcoming
                        ? FilledButton.icon(
                            onPressed: () => context.push('/appointments'),
                            icon: const Icon(Icons.add),
                            label: const Text('Prendre rendez-vous'),
                          )
                        : null,
                  ),
                ),
              ),
            )
          // #5267 : l'historique se regroupe par mois sous un en-tête ; « à
          // venir » reste une liste plate (pas de spec de groupement dessus).
          : isUpcoming
              ? ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: appointments.length,
                  itemBuilder: (context, i) => _AppointmentCard(
                    appointment: appointments[i],
                    isHistory: false,
                  ),
                )
              : _HistoryGroupedList(appointments: appointments),
    );
  }
}

// ---------------------------------------------------------------------------

/// #5267 : cartes de l'historique regroupées par mois sous un en-tête
/// (« Juillet 2026 »). Le mois est dérivé de `startsAt.toLocal()` et
/// l'ordre des groupes suit simplement celui déjà appliqué à [appointments]
/// (donc `_historySortAsc`, cf. #3801) — pas de tri recalculé ici.
class _HistoryGroupedList extends StatelessWidget {
  const _HistoryGroupedList({required this.appointments});
  final List<Appointment> appointments;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    int? lastYear;
    int? lastMonth;
    for (final appointment in appointments) {
      final local = appointment.startsAt.toLocal();
      if (local.year != lastYear || local.month != lastMonth) {
        lastYear = local.year;
        lastMonth = local.month;
        children.add(_MonthHeader(year: local.year, month: local.month));
      }
      children.add(
        _AppointmentCard(appointment: appointment, isHistory: true),
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: children,
    );
  }
}

/// En-tête de groupe mensuel (maquette design-v2, point #5 « Groupement par
/// mois ») : libellé 12,5px/600, letter-spacing .4px, uppercase, `n500`,
/// souligné d'un trait `n200`.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.year, required this.month});
  final int year;
  final int month;

  static const _monthNames = [
    'Janvier',
    'Février',
    'Mars',
    'Avril',
    'Mai',
    'Juin',
    'Juillet',
    'Août',
    'Septembre',
    'Octobre',
    'Novembre',
    'Décembre',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: NubiaColors.n200)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '${_monthNames[month - 1]} $year'.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: NubiaColors.n500,
                ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.appointment, required this.isHistory});
  final Appointment appointment;
  // #5271 : les chips de synthèse documentaire (compte-rendu/ordonnances) ne
  // doivent apparaître que sous une carte de l'onglet Historique, jamais sur
  // un RDV à venir — `isHistory` reflète l'onglet, pas le statut du RDV.
  final bool isHistory;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: NubiaCard(
        // #5268 : fond légèrement retiré sur l'historique (RDV passé) —
        // `#FCFCFB` au lieu du blanc `n0` des cartes « à venir ».
        backgroundColor: isHistory ? const Color(0xFFFCFCFB) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NubiaAvatar(initials: _initials(appointment.practitionerName)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Praticien en titre : un humain cherche d'abord chez QUI
                      // il a rendez-vous (le motif passe en secondaire).
                      Text(
                        appointment.practitionerName,
                        style: textTheme.titleSmall,
                      ),
                      // #5563/#5593 : sans ça, un tuteur avec plusieurs
                      // dépendants ne peut pas distinguer en un coup d'oeil un
                      // RDV pris pour lui-même d'un RDV pris pour un
                      // dépendant nommé (must ouvrir le détail ou deviner via
                      // le motif texte libre sinon).
                      if (!appointment.beneficiaryIsSelf &&
                          appointment.beneficiaryName != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Pour ${appointment.beneficiaryName}',
                          style: textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        // #3825 : pas de « · » pendant quand la spécialité est vide.
                        // #4831 : idem quand c'est le motif qui est vide.
                        appointment.motif.isEmpty
                            ? appointment.practitionerSpecialty
                            : appointment.practitionerSpecialty.isEmpty
                                ? appointment.motif
                                : '${appointment.motif} · ${appointment.practitionerSpecialty}',
                        style: textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusPill(status: appointment.status),
              ],
            ),
            const SizedBox(height: 12),
            _IconRow(
              icon: Icons.calendar_today_outlined,
              label: _formatDateTime(appointment.startsAt),
              // #5268 : rail neutralisé (teinte stone `n500`) sur une carte
              // passée — plus aucun brand une fois le RDV dans l'historique.
              color: isHistory
                  ? NubiaColors.n500
                  : Theme.of(context).colorScheme.primary,
            ),
            if (appointment.cabinetAddress != null) ...[
              const SizedBox(height: 4),
              _IconRow(
                icon: Icons.location_on_outlined,
                label: appointment.cabinetAddress!,
              ),
            ],
            if (appointment.status == AppointmentStatus.noShow) ...[
              const SizedBox(height: 4),
              _IconRow(
                icon: Icons.info,
                label: appointment.noShowFeeCents != null
                    ? 'Non présenté — facturé '
                        '${formatQuoteCents(appointment.noShowFeeCents!)} '
                        'selon la charte du cabinet'
                    : 'Non présenté',
                color: NubiaColors.n500,
              ),
            ],
            if (appointment.isUpcoming ||
                appointment.canCancel ||
                appointment.canModify ||
                isHistory) ...[
              const SizedBox(height: 12),
              _ActionButtons(appointment: appointment, isHistory: isHistory),
            ],
            if (isHistory &&
                (appointment.hasReport ||
                    appointment.prescriptionCount > 0)) ...[
              const SizedBox(height: 12),
              _DocumentSummaryChips(appointment: appointment),
            ],
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    // Retire le préfixe de civilité (« Dr », « Dr. », « Pr », « M. »…) pour ne
    // pas polluer les initiales : « Dr Amélie Dubois » → « AD », pas « DD ».
    final cleaned = name
        .replaceAll(
          RegExp(r'^(Dr|Dr\.|Pr|Pr\.|M\.|Mme|Mlle)\s+', caseSensitive: false),
          '',
        )
        .trim();
    final parts =
        cleaned.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  String _formatDateTime(DateTime utc) {
    const weekdays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    const months = [
      'jan',
      'fév',
      'mar',
      'avr',
      'mai',
      'jun',
      'jul',
      'aoû',
      'sep',
      'oct',
      'nov',
      'déc',
    ];
    // #4620/#4618 : startsAt vient de DateTime.parse() sur un ISO +00:00
    // (isUtc == true) — lire .hour/.day/.weekday bruts affichait l'heure UTC
    // au lieu de l'heure locale (-2h en été / -1h en hiver pour Europe/Paris).
    final dt = utc.toLocal();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${weekdays[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]} à $h:$m';
  }
}

// ---------------------------------------------------------------------------

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.appointment, required this.isHistory});
  final Appointment appointment;
  final bool isHistory;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // #5270 : un RDV terminé facturé propose en plus d'accéder à la
        // facture quand le montant est connu (« Reprendre RDV » reste
        // affiché juste après pour tout l'historique, cf. #5269).
        if (appointment.status == AppointmentStatus.completed &&
            appointment.invoiceAmountCents != null)
          NubiaButton(
            key: Key('invoice_${appointment.id}'),
            label:
                'Facture · ${formatQuoteCents(appointment.invoiceAmountCents!, alwaysShowDecimals: true)}',
            size: NubiaButtonSize.sm,
            icon: Icons.receipt_long,
            onPressed: () => context.push('/documents'),
          ),
        // #5269 : action primaire de l'historique (Terminé/Absent/Annulé) —
        // relance une prise de RDV avec le même praticien (son nom est
        // transmis pour pré-remplir la recherche). Sans check-in/modifier/
        // annuler sur l'historique : ces actions "à venir" n'ont plus
        // d'objet une fois le RDV passé.
        if (isHistory)
          NubiaButton(
            key: Key('rebook_${appointment.id}'),
            label: 'Reprendre RDV',
            variant: NubiaButtonVariant.secondary,
            size: NubiaButtonSize.sm,
            icon: Icons.replay,
            // #5269 : practitionerId peut être vide (l'API ne l'expose pas
            // toujours) — la reprise reste possible, simplement sans
            // pré-sélection du praticien.
            onPressed: () => context.push(
              '/appointments',
              extra: appointment.practitionerId.isNotEmpty
                  ? appointment.practitionerName
                  : null,
            ),
          ),
        if (appointment.isUpcoming)
          NubiaButton(
            key: Key('checkin_${appointment.id}'),
            label: 'Check-in',
            size: NubiaButtonSize.sm,
            icon: Icons.check_circle_outline,
            onPressed: () => context
                .read<MesRdvBloc>()
                .add(MesRdvCheckinRequested(appointment.id)),
          ),
        if (appointment.isUpcoming)
          NubiaButton(
            key: Key('questionnaire_${appointment.id}'),
            label: 'Questionnaire médical',
            variant: NubiaButtonVariant.secondary,
            size: NubiaButtonSize.sm,
            icon: Icons.assignment_outlined,
            onPressed: () => context.push(
              '/questionnaire-medical/${appointment.cabinetId}',
            ),
          ),
        if (appointment.canModify)
          NubiaButton(
            key: Key('modify_${appointment.id}'),
            label: 'Modifier',
            variant: NubiaButtonVariant.secondary,
            size: NubiaButtonSize.sm,
            icon: Icons.edit_calendar_outlined,
            onPressed: () async {
              final modified =
                  await context.push<bool>('/rdv/${appointment.id}/modifier');
              if (modified == true && context.mounted) {
                context.read<MesRdvBloc>().add(const MesRdvLoadRequested());
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Rendez-vous modifié')),
                );
              }
            },
          ),
        if (appointment.canCancel)
          NubiaButton(
            key: Key('cancel_${appointment.id}'),
            label: 'Annuler',
            variant: NubiaButtonVariant.destructive,
            size: NubiaButtonSize.sm,
            icon: Icons.cancel_outlined,
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Annuler ce RDV ?'),
                  content: const Text('Cette action est irréversible.'),
                  actions: [
                    TextButton(
                      key: const Key('dialog_dismiss'),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Annuler'),
                    ),
                    FilledButton(
                      key: const Key('dialog_confirm'),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Confirmer'),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                context
                    .read<MesRdvBloc>()
                    .add(MesRdvCancelRequested(appointment));
              }
            },
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// #5271 : rangée de chips de synthèse documentaire (compte-rendu /
/// ordonnance(s)) sous une carte historique — chaque chip n'apparaît que si
/// le document correspondant existe (pilotage par les données du RDV).
class _DocumentSummaryChips extends StatelessWidget {
  const _DocumentSummaryChips({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (appointment.hasReport)
          const _SummaryChip(
            icon: Icons.description,
            label: 'Compte-rendu',
          ),
        if (appointment.prescriptionCount > 0)
          _SummaryChip(
            icon: Icons.medication,
            label: appointment.prescriptionCount == 1
                ? '1 ordonnance'
                : '${appointment.prescriptionCount} ordonnances',
          ),
      ],
    );
  }
}

/// Chip de synthèse statique (non interactive) : icône 14px `n500` + libellé
/// 12px/500 `n600`, fond `n100`, radius 8, padding 5×9 — cf. maquette
/// design-v2 (distincte de [NubiaChip], pensée pour un filtre sélectionnable).
class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: NubiaColors.n100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: NubiaColors.n500),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: NubiaColors.n600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _IconRow extends StatelessWidget {
  const _IconRow({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: fg),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final AppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, variant) = switch (status) {
      AppointmentStatus.confirmed => ('Confirmé', StatusPillVariant.success),
      AppointmentStatus.requested => ('En attente', StatusPillVariant.warning),
      AppointmentStatus.checkedIn => ('Arrivé', StatusPillVariant.info),
      AppointmentStatus.inProgress => ('En cours', StatusPillVariant.warning),
      AppointmentStatus.cancelled => ('Annulé', StatusPillVariant.error),
      AppointmentStatus.completed => ('Terminé', StatusPillVariant.info),
      AppointmentStatus.noShow => ('Absent', StatusPillVariant.error),
    };
    return StatusPill(label: label, variant: variant);
  }
}
