import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'waiting_room_bloc.dart';
import 'waiting_room_event.dart';
import 'waiting_room_state.dart';
import 'widgets/waiting_room_kpis.dart';

/// Seuil critique d'attente (cf. KPI « au-delà de 30 min », #5170/#5173).
const int _criticalWaitThresholdMinutes = 30;

/// Entrée la plus en retard au-delà du seuil critique, ou `null` si aucune
/// n'y est (#5170) — c'est celle que le bandeau nomme.
WaitingRoomEntry? _mostOverdueEntry(List<WaitingRoomEntry> entries) {
  WaitingRoomEntry? mostOverdue;
  for (final entry in entries) {
    if (entry.waitSoFar.inMinutes < _criticalWaitThresholdMinutes) continue;
    if (mostOverdue == null || entry.waitSoFar > mostOverdue.waitSoFar) {
      mostOverdue = entry;
    }
  }
  return mostOverdue;
}

/// Body-only content for the waiting room. Can be embedded in any layout
/// that provides [WaitingRoomBloc] via [BlocProvider] (e.g. [ProShell]
/// bodyBuilder or the full-page [WaitingRoomPage]).
class WaitingRoomBody extends StatefulWidget {
  const WaitingRoomBody({super.key});

  @override
  State<WaitingRoomBody> createState() => _WaitingRoomBodyState();
}

class _WaitingRoomBodyState extends State<WaitingRoomBody> {
  @override
  void initState() {
    super.initState();
    context.read<WaitingRoomBloc>().add(const WaitingRoomLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WaitingRoomBloc, WaitingRoomState>(
      builder: (context, state) {
        if (state is WaitingRoomLoaded) {
          final entries = state.entries;
          if (entries.isEmpty) {
            return const NubiaEmptyState(
              key: Key('waiting_room_empty'),
              icon: Icons.people_outline,
              title: 'Salle d\'attente vide',
              subtitle: NubiaL10n.noWaitingRoom,
            );
          }
          final mostOverdue = _mostOverdueEntry(entries);
          return Column(
            children: [
              if (mostOverdue != null) _OverThresholdBanner(entry: mostOverdue),
              Expanded(
                child: ListView.builder(
                  key: const Key('waiting_room_list'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: entries.length,
                  itemBuilder: (_, i) => _WaitingEntryTile(
                    entry: entries[i],
                    position: i + 1,
                  ),
                ),
              ),
            ],
          );
        }
        if (state is WaitingRoomError) {
          return NubiaErrorWidget(
            message: state.message,
            onRetry: () => context
                .read<WaitingRoomBloc>()
                .add(const WaitingRoomLoadRequested()),
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}

/// Bandeau d'alerte affiché au-dessus de la liste quand au moins une
/// entrée dépasse le seuil critique (#5170) : nomme le patient le plus en
/// retard et propose « Prévenir le praticien ». Ne montre aucune donnée
/// praticien (nom, heure de séance) faute d'extension d'entité (ticket
/// colonne Praticien) — cf. corps de l'issue.
class _OverThresholdBanner extends StatelessWidget {
  const _OverThresholdBanner({required this.entry});

  final WaitingRoomEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final minutes = entry.waitSoFar.inMinutes;
    return Container(
      key: const Key('waiting_room_alert_banner'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.warningBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error, color: tokens.warningFg),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${entry.patientName} attend depuis $minutes min',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.warningFg,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          NubiaButton(
            key: const Key('waiting_room_notify_practitioner_button'),
            label: 'Prévenir le praticien',
            size: NubiaButtonSize.sm,
            variant: NubiaButtonVariant.secondary,
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Notification du praticien à venir'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WaitingRoomPage extends StatelessWidget {
  const WaitingRoomPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('waiting_room_scaffold'),
      appBar: AppBar(
        title: Row(
          children: [
            Text(NubiaL10n.waitingRoom),
            const SizedBox(width: 24),
            Expanded(
              child: BlocBuilder<WaitingRoomBloc, WaitingRoomState>(
                builder: (context, state) => state is WaitingRoomLoaded
                    ? WaitingRoomKpiBar(entries: state.entries)
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: NubiaL10n.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<WaitingRoomBloc>()
                .add(const WaitingRoomLoadRequested()),
          ),
        ],
      ),
      floatingActionButton: BlocBuilder<WaitingRoomBloc, WaitingRoomState>(
        builder: (context, state) {
          final hasPatients =
              state is WaitingRoomLoaded && state.entries.isNotEmpty;
          return FloatingActionButton.extended(
            onPressed: hasPatients
                ? () => context
                    .read<WaitingRoomBloc>()
                    .add(const WaitingRoomCallNextRequested())
                : null,
            icon: const Icon(Icons.skip_next),
            label: Text(NubiaL10n.callNext),
          );
        },
      ),
      body: const WaitingRoomBody(),
    );
  }
}

class _WaitingEntryTile extends StatelessWidget {
  const _WaitingEntryTile({required this.entry, required this.position});

  final WaitingRoomEntry entry;
  final int position;

  static String _initials(String name) {
    final trimmed = name.trim();
    return trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final reason = entry.reason;
    final appointmentTime = entry.appointmentTime;
    final timeLabel = appointmentTime != null
        ? '${appointmentTime.hour.toString().padLeft(2, '0')}:'
            '${appointmentTime.minute.toString().padLeft(2, '0')}'
        : null;
    final subtitle = reason == null || reason.isEmpty
        ? null
        : timeLabel == null
            ? reason
            : '$reason · RDV $timeLabel';

    // Urgence sans rendez-vous : aucun praticien attribué (#5171).
    final bool isUnassigned = entry.appointmentId == null;

    return ListRow(
      leading: NubiaAvatar(initials: _initials(entry.patientName)),
      title: entry.patientName,
      subtitle: subtitle,
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          StatusPill(
            label: isUnassigned ? 'Sans RDV' : 'En attente',
            variant:
                isUnassigned ? StatusPillVariant.warning : StatusPillVariant.info,
          ),
          if (isUnassigned) ...[
            const SizedBox(height: 4),
            const StatusPill(
              label: 'Non attribué',
              variant: StatusPillVariant.neutral,
            ),
          ],
          if (entry.estimatedWaitMinutes != null) ...[
            const SizedBox(height: 4),
            Text(
              '~${entry.estimatedWaitMinutes} min',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.textTertiary,
                  ),
            ),
          ],
          if (isUnassigned) ...[
            const SizedBox(height: 4),
            NubiaButton(
              key: Key('waiting_entry_assign_button_${entry.id}'),
              label: 'Attribuer',
              icon: Icons.person_add,
              size: NubiaButtonSize.sm,
              variant: NubiaButtonVariant.secondary,
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Attribution d'un praticien à venir"),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
