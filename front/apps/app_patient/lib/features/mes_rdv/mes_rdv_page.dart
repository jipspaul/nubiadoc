import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:share_plus/share_plus.dart';

import 'appointment_formatting.dart';
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

  // Libellés verbatim maquette — énoncent l'ordre COURANT (pas la cible du
  // tap), cf. #5266 : le tooltip précédent décrivait l'ordre obtenu après
  // bascule, pas celui affiché à l'écran.
  String get _sortLabel => _selectedIndex == 0
      ? (_currentSortAsc ? 'Plus proche d\'abord' : 'Plus lointain d\'abord')
      : (_currentSortAsc ? 'Plus ancien d\'abord' : 'Plus récent d\'abord');

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
                  counts: [upcoming.length, history.length],
                  selectedIndex: _selectedIndex,
                  onChanged: (i) {
                    setState(() => _selectedIndex = i);
                    if (i == 1) {
                      context
                          .read<MesRdvBloc>()
                          .add(const MesRdvHistoryRequested());
                    }
                  },
                ),
              ),
              _SortChip(
                key: const Key('sort_button'),
                label: _sortLabel,
                onTap: _toggleSort,
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

/// Puce de tri (maquette design-v2, point #4) : remplace l'`IconButton`
/// dont le libellé ne vivait que dans un `tooltip` (inatteignable au
/// doigt) par une puce qui énonce l'ordre courant en toutes lettres.
/// `swap_vert` 15px + libellé 12,5px/500 `n500`, bordure `n200`, fond
/// blanc, radius 99, padding 5/10/5/8.
class _SortChip extends StatelessWidget {
  const _SortChip({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NubiaColors.n0,
      shape: const StadiumBorder(side: BorderSide(color: NubiaColors.n200)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.swap_vert, size: 15, color: NubiaColors.n500),
              const SizedBox(width: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: NubiaColors.n500,
                    ),
              ),
            ],
          ),
        ),
      ),
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
          // #5267 : l'historique se regroupe par mois sous un en-tête ; #5262
          // fait de même pour « à venir », mais par jour, avec en-têtes
          // collants (SliverPersistentHeader) — le regroupement mensuel ne
          // s'y prête pas (horizon trop court).
          : isUpcoming
              ? _UpcomingGroupedList(appointments: appointments)
              : _HistoryGroupedList(appointments: appointments),
    );
  }
}

// ---------------------------------------------------------------------------

/// #5262 : cartes de l'onglet « À venir » regroupées par jour sous un en-tête
/// collant (`SliverPersistentHeader(pinned: true)`). Le jour est dérivé de
/// `startsAt.toLocal()` et l'ordre des groupes suit celui déjà appliqué à
/// [appointments] (donc `_upcomingSortAsc`, cf. #3801) — pas de tri
/// recalculé ici.
class _UpcomingGroupedList extends StatelessWidget {
  const _UpcomingGroupedList({required this.appointments});
  final List<Appointment> appointments;

  @override
  Widget build(BuildContext context) {
    final groups = _groupByDay(appointments);
    final today = DateTime.now();
    final slivers = <Widget>[
      const SliverToBoxAdapter(child: SizedBox(height: 8)),
    ];
    for (final group in groups) {
      final isToday = group.date.year == today.year &&
          group.date.month == today.month &&
          group.date.day == today.day;
      slivers.add(
        SliverPersistentHeader(
          pinned: true,
          delegate: _DayHeaderDelegate(date: group.date, isToday: isToday),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: _AppointmentCard(
                  appointment: group.appointments[i],
                  isHistory: false,
                ),
              ),
              childCount: group.appointments.length,
            ),
          ),
        ),
      );
    }
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: slivers,
    );
  }

  static List<_DayGroup> _groupByDay(List<Appointment> appointments) {
    final groups = <_DayGroup>[];
    DateTime? lastDay;
    for (final appointment in appointments) {
      final local = appointment.startsAt.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      if (lastDay == null || day != lastDay) {
        lastDay = day;
        groups.add(_DayGroup(day, []));
      }
      groups.last.appointments.add(appointment);
    }
    return groups;
  }
}

class _DayGroup {
  _DayGroup(this.date, this.appointments);
  final DateTime date;
  final List<Appointment> appointments;
}

class _DayHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _DayHeaderDelegate({required this.date, required this.isToday});
  final DateTime date;
  final bool isToday;

  static const double _extent = 36;

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: _DayHeader(date: date, isToday: isToday),
    );
  }

  @override
  bool shouldRebuild(covariant _DayHeaderDelegate oldDelegate) =>
      oldDelegate.date != date || oldDelegate.isToday != isToday;
}

/// En-tête de jour (maquette design-v2, onglet « À venir », `.day`) :
/// libellé (`.d`) 12,5px/600, letter-spacing .4px, `n500` + trait fin `n200`
/// qui remplit la largeur restante. Jour courant (`.day.now`) : libellé
/// « Aujourd'hui » en `brand700`.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date, required this.isToday});
  final DateTime date;
  final bool isToday;

  static const _weekdays = [
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
    'Dimanche',
  ];

  static const _months = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  String get _label => isToday
      ? 'Aujourd\'hui'
      : '${_weekdays[date.weekday - 1]} ${date.day} ${_months[date.month - 1]}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Text(
            _label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: isToday ? NubiaColors.brand700 : NubiaColors.n500,
                ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: NubiaColors.n200)),
              ),
              child: SizedBox(height: 1),
            ),
          ),
        ],
      ),
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
                // #5261 : le rail de date (jour/n°/heure) remplace l'avatar
                // d'initiales comme repère visuel primaire sur une carte
                // à venir — la variante « passée » (`.rail.past`) est traitée
                // par un autre ticket, l'historique garde donc l'avatar ici.
                isHistory
                    ? NubiaAvatar(
                        initials: appointmentInitials(
                            appointment.practitionerName))
                    : _DateRail(startsAt: appointment.startsAt),
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
              label: formatAppointmentDateTime(appointment.startsAt),
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
            // #5265 : maquette design-v2 point #3 — le check-in n'a de sens
            // que le jour J (un RDV confirmé isUpcoming peut être dans trois
            // semaines) et doit disparaître dès `checkedIn`, même si le RDV
            // reste dans la fenêtre du jour.
            if (_isCheckinDay(appointment.startsAt) &&
                appointment.status != AppointmentStatus.checkedIn) ...[
              const SizedBox(height: 12),
              _CheckinBand(appointment: appointment),
            ],
          ],
        ),
      ),
    );
  }

  static bool _isCheckinDay(DateTime startsAt) {
    final now = DateTime.now();
    final local = startsAt.toLocal();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }

}

// ---------------------------------------------------------------------------

/// Rail de date (maquette design-v2, issue #5261) : remplace l'avatar
/// d'initiales en tête de carte « à venir » — jour abrégé / n° du jour /
/// heure empilés, 52px de large, radius 13, fond `brand50`, bordure
/// `brand100`, texte `brand700`. Jour et heure dérivés de `startsAt.toLocal()`
/// (jamais UTC, cf. #4620/#4618). La variante passée (`.rail.past`) est hors
/// scope, cf. [_AppointmentCard].
class _DateRail extends StatelessWidget {
  const _DateRail({required this.startsAt});
  final DateTime startsAt;

  static const _weekdaysAbbrev = [
    'Lun',
    'Mar',
    'Mer',
    'Jeu',
    'Ven',
    'Sam',
    'Dim',
  ];

  @override
  Widget build(BuildContext context) {
    final local = startsAt.toLocal();
    final day = _weekdaysAbbrev[local.weekday - 1].toUpperCase();
    final number = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: NubiaColors.brand50,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: NubiaColors.brand100),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            day,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: NubiaColors.brand700.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            number,
            style: GoogleFonts.fraunces(
              fontSize: 23,
              fontWeight: FontWeight.w600,
              color: NubiaColors.brand700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$hour:$minute',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: NubiaColors.brand700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Bandeau check-in (maquette design-v2, point #3) : sorti du `Wrap`
/// d'actions pour devenir un bandeau pleine largeur en bas de carte, visible
/// uniquement le jour du RDV (cf. `_isCheckinDay` dans [_AppointmentCard]).
/// Fond `brand700`, texte blanc, icône `how_to_reg` 20px ; bouton fond blanc
/// / texte `brand700`, radius 10, hauteur 36.
class _CheckinBand extends StatelessWidget {
  const _CheckinBand({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final local = appointment.startsAt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: NubiaColors.brand700,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.how_to_reg, size: 20, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13, color: Colors.white),
                children: [
                  const TextSpan(text: 'Vous êtes attendu à '),
                  TextSpan(
                    text: '$h:$m',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: ' — signalez votre arrivée'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 36,
            child: FilledButton(
              key: Key('checkin_${appointment.id}'),
              onPressed: () => context
                  .read<MesRdvBloc>()
                  .add(MesRdvCheckinRequested(appointment.id)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: NubiaColors.brand700,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Je suis là',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.appointment, required this.isHistory});
  final Appointment appointment;
  final bool isHistory;

  @override
  Widget build(BuildContext context) {
    if (isHistory) {
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
          // #5269 : action primaire de l'historique (Terminé/Absent/Annulé)
          // — relance une prise de RDV avec le même praticien (son nom est
          // transmis pour pré-remplir la recherche). Sans check-in/modifier/
          // annuler sur l'historique : ces actions "à venir" n'ont plus
          // d'objet une fois le RDV passé.
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
        ],
      );
    }

    // #5264 : maquette design-v2 point #2 — le `Wrap` de 4 boutons de même
    // poids devient UNE action contextuelle primaire pleine largeur (`.act`)
    // + un `PopupMenuButton` (`.more`) portant les actions secondaires, avec
    // « Annuler » isolé en bas du menu. La destruction n'est plus à un
    // doigt de la confirmation.
    return Row(
      children: [
        if (appointment.isUpcoming) ...[
          Expanded(child: _PrimaryAction(appointment: appointment)),
          const SizedBox(width: 8),
        ],
        _MoreActionsMenu(appointment: appointment),
      ],
    );
  }
}

/// Action contextuelle primaire (`.act`) : flex:1, hauteur 40, radius 11,
/// bordure `n200`, fond blanc, label 13,5px/600 `n800`, icône `n500`.
/// #5264 : seule action affichée à ce niveau — le reste passe dans le menu
/// `⋯` ([_MoreActionsMenu]).
class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return _ActRowButton(
      key: Key('questionnaire_${appointment.id}'),
      icon: Icons.assignment_outlined,
      label: 'Questionnaire médical',
      onPressed: () => context.push(
        '/questionnaire-medical/${appointment.cabinetId}',
      ),
    );
  }
}

/// Bouton `.act` partagé par [_PrimaryAction] : bordure `n200`, fond blanc,
/// radius 11, hauteur 40.
class _ActRowButton extends StatelessWidget {
  const _ActRowButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Material(
        color: NubiaColors.n0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: const BorderSide(color: NubiaColors.n200),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: NubiaColors.n500),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: NubiaColors.n800,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Actions secondaires portées par le menu `⋯` (`.more`, carré 40px, même
/// bordure/fond que `.act`, icône `more_horiz` `n500`) : Modifier, Ajouter
/// au calendrier, Contacter le cabinet puis Annuler — isolé en dernier
/// (séparateur) et en `danger/fg`. Modifier/Annuler restent gatés par
/// `canModify`/`canCancel` (#3804, non régressés).
class _MoreActionsMenu extends StatelessWidget {
  const _MoreActionsMenu({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: NubiaColors.n0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: const BorderSide(color: NubiaColors.n200),
        ),
        clipBehavior: Clip.antiAlias,
        child: PopupMenuButton<_RdvMenuAction>(
          key: Key('more_actions_${appointment.id}'),
          tooltip: 'Plus d\'actions',
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.more_horiz, color: NubiaColors.n500),
          onSelected: (action) => _onSelected(context, action),
          itemBuilder: (context) => [
            if (appointment.canModify)
              PopupMenuItem(
                key: Key('modify_${appointment.id}'),
                value: _RdvMenuAction.modify,
                child: const _MenuItemLabel(
                  icon: Icons.edit_calendar_outlined,
                  label: 'Modifier',
                ),
              ),
            PopupMenuItem(
              key: Key('add_to_calendar_${appointment.id}'),
              value: _RdvMenuAction.addToCalendar,
              child: const _MenuItemLabel(
                icon: Icons.event_outlined,
                label: 'Ajouter au calendrier',
              ),
            ),
            if (appointment.cabinetPhone != null)
              PopupMenuItem(
                key: Key('contact_cabinet_${appointment.id}'),
                value: _RdvMenuAction.contactCabinet,
                child: const _MenuItemLabel(
                  icon: Icons.call_outlined,
                  label: 'Contacter le cabinet',
                ),
              ),
            if (appointment.canCancel) ...[
              const PopupMenuDivider(),
              PopupMenuItem(
                key: Key('cancel_${appointment.id}'),
                value: _RdvMenuAction.cancel,
                child: const _MenuItemLabel(
                  icon: Icons.cancel_outlined,
                  label: 'Annuler',
                  color: NubiaColors.dangerFg,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _onSelected(BuildContext context, _RdvMenuAction action) async {
    switch (action) {
      case _RdvMenuAction.modify:
        final modified =
            await context.push<bool>('/rdv/${appointment.id}/modifier');
        if (modified == true && context.mounted) {
          context.read<MesRdvBloc>().add(const MesRdvLoadRequested());
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rendez-vous modifié')),
          );
        }
      case _RdvMenuAction.addToCalendar:
        Share.share(
          _calendarSummary(appointment),
          subject: 'Rendez-vous · ${appointment.practitionerName}',
        );
      case _RdvMenuAction.contactCabinet:
        callPhoneNumber(appointment.cabinetPhone!);
      case _RdvMenuAction.cancel:
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
    }
  }
}

enum _RdvMenuAction { modify, addToCalendar, contactCabinet, cancel }

/// Résumé texte du RDV partagé par « Ajouter au calendrier » — en attendant
/// une intégration native à l'agenda de l'appareil (hors scope #5264).
String _calendarSummary(Appointment appointment) {
  final local = appointment.startsAt.toLocal();
  final date = '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
  final time = '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  final summary = StringBuffer(
    'RDV avec ${appointment.practitionerName} le $date à $time',
  );
  if (appointment.cabinetAddress != null) {
    summary.write(' — ${appointment.cabinetAddress}');
  }
  return summary.toString();
}

class _MenuItemLabel extends StatelessWidget {
  const _MenuItemLabel({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color ?? NubiaColors.n500),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: color ?? NubiaColors.n800,
            fontWeight: FontWeight.w500,
          ),
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
