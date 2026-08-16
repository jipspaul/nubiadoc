import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Panneau « Flux du jour » (#5380, colonne principale du tableau de bord) :
/// timeline des RDV du jour, avec lien « Ouvrir l'agenda » vers `/agenda`.
/// Source : les `AgendaEntry` du jour, déjà chargées et triées par
/// `DashboardBloc` (`GetCabinetAgendaUseCase`) — aucun appel réseau
/// supplémentaire.
class TodayFlowCard extends StatelessWidget {
  const TodayFlowCard({super.key, required this.entries});

  final List<AgendaEntry> entries;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return NubiaCard(
      key: const Key('today_flow_card'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Flux du jour',
                    style: textTheme.titleMedium?.copyWith(color: cs.onSurface),
                  ),
                ),
                InkWell(
                  key: const Key('today_flow_card_open_link'),
                  onTap: () => context.push('/agenda'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Ouvrir l'agenda",
                        style: textTheme.bodySmall?.copyWith(
                          color: NubiaColors.brand700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward,
                        size: 14,
                        color: NubiaColors.brand700,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (entries.isEmpty)
            const Padding(
              key: Key('today_flow_empty'),
              padding: EdgeInsets.only(bottom: 8),
              child: NubiaEmptyState(
                icon: Icons.event_busy_outlined,
                title: "Aucun rendez-vous aujourd'hui",
              ),
            )
          else
            for (int i = 0; i < entries.length; i++)
              _TodayFlowRow(
                entry: entries[i],
                showDivider: i < entries.length - 1,
              ),
        ],
      ),
    );
  }
}

class _TodayFlowRow extends StatelessWidget {
  const _TodayFlowRow({required this.entry, required this.showDivider});

  final AgendaEntry entry;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    final time = '${entry.startsAt.hour.toString().padLeft(2, '0')}:'
        '${entry.startsAt.minute.toString().padLeft(2, '0')}';
    final patientName =
        entry.patientName != null && entry.patientName!.isNotEmpty
            ? entry.patientName!
            : 'Patient';

    final subtitleParts = <String>[
      if (entry.motif != null && entry.motif!.isNotEmpty) entry.motif!,
      if (entry.practitionerName.isNotEmpty) entry.practitionerName,
    ];

    final Widget row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 44,
              child: Text(
                time,
                style: textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 12),
            NubiaAvatar(initials: _initialsFrom(entry.patientName), radius: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patientName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitleParts.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitleParts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            StatusPill(
              label: _statusLabel(entry),
              variant: _statusVariant(entry),
            ),
          ],
        ),
      ),
    );

    final Widget styled = entry.isDone
        ? Opacity(opacity: 0.5, child: row)
        : (entry.isInProgress || entry.isCheckedIn)
            ? DecoratedBox(
                decoration: BoxDecoration(color: tokens.primarySubtleBg),
                child: row,
              )
            : row;

    if (!showDivider) {
      return KeyedSubtree(
        key: Key('today_flow_row_${entry.id}'),
        child: styled,
      );
    }

    return KeyedSubtree(
      key: Key('today_flow_row_${entry.id}'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          styled,
          Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
        ],
      ),
    );
  }
}

/// Libellé de la pastille de statut (mapping verbatim de la maquette #5380).
String _statusLabel(AgendaEntry entry) {
  if (entry.isDone) return 'Terminé';
  if (entry.isInProgress || entry.isCheckedIn) return 'En salle';
  if (entry.isPending) return 'Non confirmé';
  return 'À venir';
}

/// Variant sémantique de la pastille de statut (mapping verbatim de la
/// maquette #5380).
StatusPillVariant _statusVariant(AgendaEntry entry) {
  if (entry.isDone) return StatusPillVariant.success;
  if (entry.isInProgress || entry.isCheckedIn) return StatusPillVariant.info;
  if (entry.isPending) return StatusPillVariant.error;
  return StatusPillVariant.neutral;
}

String _initialsFrom(String? name) {
  if (name == null || name.trim().isEmpty) return '–';
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length == 1) {
    final p = parts.first;
    return (p.length <= 2 ? p : p.substring(0, 2)).toUpperCase();
  }
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}
