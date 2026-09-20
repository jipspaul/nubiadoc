//! Section « Séances » d'un plan de traitement (#7172, DP-F16.c) — liste des
//! séances proposées par l'algorithme de découpage (#7173), réordonnables
//! par glisser-déposer, réglage de la durée par défaut d'un acte avant
//! proposition, sélection d'un créneau proposé et création du RDV lié.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../treatment_sessions_cubit.dart';
import '../treatment_status_style.dart';

class PlanSessionsSection extends StatelessWidget {
  const PlanSessionsSection({super.key, required this.planId});

  final String planId;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TreatmentSessionsCubit, TreatmentSessionsState>(
      listenWhen: (prev, curr) =>
          curr is TreatmentSessionsLoaded &&
          curr.actionError != null &&
          (prev is! TreatmentSessionsLoaded ||
              prev.actionError != curr.actionError),
      listener: (context, state) {
        if (state is TreatmentSessionsLoaded && state.actionError != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.actionError!)));
        }
      },
      builder: (context, state) {
        final busy = state is TreatmentSessionsLoaded && state.busy;
        return Column(
          key: Key('treatment_plan_sessions_$planId'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Séances',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                NubiaButton(
                  key: Key('treatment_plan_propose_sessions_$planId'),
                  variant: NubiaButtonVariant.secondary,
                  size: NubiaButtonSize.sm,
                  icon: Icons.auto_awesome_motion,
                  label: 'Proposer des séances',
                  isLoading: busy,
                  onPressed:
                      busy ? null : () => _openProposeDialog(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (state is! TreatmentSessionsLoaded ||
                state.sessions.isEmpty)
              Text(
                'Aucune séance proposée.',
                key: Key('treatment_plan_sessions_empty_$planId'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: NubiaColors.n500),
              )
            else
              _SessionsList(planId: planId, state: state),
          ],
        );
      },
    );
  }

  Future<void> _openProposeDialog(BuildContext context) async {
    final cubit = context.read<TreatmentSessionsCubit>();
    final durationMin = await showDialog<int>(
      context: context,
      builder: (_) => _ProposeSessionsDialog(planId: planId),
    );
    if (durationMin != null) {
      await cubit.propose(defaultDurationMin: durationMin);
    }
  }
}

/// Liste réordonnable par glisser-déposer (#7172) — aucun endpoint ne
/// persiste l'ordre côté API, réordonnancement visuel géré par
/// [TreatmentSessionsCubit.reorder].
class _SessionsList extends StatelessWidget {
  const _SessionsList({required this.planId, required this.state});

  final String planId;
  final TreatmentSessionsLoaded state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TreatmentSessionsCubit>();
    return ReorderableListView.builder(
      key: Key('treatment_plan_sessions_list_$planId'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: state.sessions.length,
      onReorder: cubit.reorder,
      itemBuilder: (context, index) {
        final session = state.sessions[index];
        final expanded = state.expandedSessionId == session.id;
        return _SessionListItem(
          key: Key('treatment_session_${session.id}'),
          index: index,
          session: session,
          busy: state.busy,
          expanded: expanded,
          slots: expanded ? state.slots : const [],
          slotsLoading: expanded && state.slotsLoading,
        );
      },
    );
  }
}

class _SessionListItem extends StatelessWidget {
  const _SessionListItem({
    super.key,
    required this.index,
    required this.session,
    required this.busy,
    required this.expanded,
    required this.slots,
    required this.slotsLoading,
  });

  final int index;
  final TreatmentSession session;
  final bool busy;
  final bool expanded;
  final List<ProposedSlot> slots;
  final bool slotsLoading;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TreatmentSessionsCubit>();
    final textTheme = Theme.of(context).textTheme;
    final (statusLabel, statusVariant) =
        treatmentSessionStatusStyle(session.status);
    final scheduled = session.status == 'scheduled';
    final actsCount = session.quoteItemIds.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NubiaCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  key: Key('treatment_session_drag_handle_${session.id}'),
                  child: const Icon(
                    Icons.drag_indicator,
                    size: 18,
                    color: NubiaColors.n400,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Séance ${session.position} · ${session.durationMin} min',
                    style:
                        textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$actsCount acte${actsCount > 1 ? 's' : ''}',
                  key: Key('treatment_session_acts_count_${session.id}'),
                  style: textTheme.bodySmall?.copyWith(color: NubiaColors.n500),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(width: 8),
                StatusPill(
                  key: Key('treatment_session_status_${session.id}'),
                  label: statusLabel,
                  variant: statusVariant,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (scheduled)
              Text(
                'Rendez-vous créé.',
                key: Key('treatment_session_scheduled_${session.id}'),
                style: textTheme.bodySmall?.copyWith(color: NubiaColors.n500),
              )
            else
              NubiaButton(
                key: Key('treatment_session_slots_button_${session.id}'),
                variant: NubiaButtonVariant.tertiary,
                size: NubiaButtonSize.sm,
                icon: expanded ? Icons.expand_less : Icons.event_available,
                label: expanded ? 'Masquer les créneaux' : 'Voir les créneaux',
                onPressed: busy
                    ? null
                    : () => expanded
                        ? cubit.collapseSlots()
                        : cubit.loadSlots(session.id),
              ),
            if (expanded && !scheduled)
              _SlotsPanel(
                sessionId: session.id,
                slots: slots,
                loading: slotsLoading,
                busy: busy,
                onSelect: (slotId) => cubit.schedule(session.id, slotId),
              ),
          ],
        ),
      ),
    );
  }
}

/// Panneau des créneaux proposés pour une séance dépliée (#7172) — un chip
/// par créneau, sélection déclenche `POST .../schedule` (création du RDV).
class _SlotsPanel extends StatelessWidget {
  const _SlotsPanel({
    required this.sessionId,
    required this.slots,
    required this.loading,
    required this.busy,
    required this.onSelect,
  });

  final String sessionId;
  final List<ProposedSlot> slots;
  final bool loading;
  final bool busy;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Center(
          key: Key('treatment_session_slots_loading'),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (slots.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Aucun créneau disponible.',
          key: Key('treatment_session_slots_empty_$sessionId'),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: NubiaColors.n500),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        key: Key('treatment_session_slots_$sessionId'),
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final slot in slots)
            ActionChip(
              key: Key('treatment_session_slot_${slot.id}'),
              label: Text(_slotLabel(slot)),
              onPressed: busy ? null : () => onSelect(slot.id),
            ),
        ],
      ),
    );
  }

  String _slotLabel(ProposedSlot slot) {
    const weekdays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    const months = [
      'jan.',
      'fév.',
      'mar.',
      'avr.',
      'mai',
      'juin',
      'juil.',
      'août',
      'sep.',
      'oct.',
      'nov.',
      'déc.',
    ];
    final d = slot.startsAt;
    final h =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${weekdays[d.weekday - 1]} ${d.day} ${months[d.month - 1]} – $h';
  }
}

/// Dialogue de réglage avant proposition (#7172) — seule règle réglable
/// depuis le front pour l'instant : la durée par défaut appliquée à un acte
/// sans durée connue (`ProposeSessionsBody.default_duration_min`, #7173).
/// Les autres règles du cabinet (durée max, séparation d'arcade, secteur,
/// endo multiples) sont résolues côté API (`cabinet_session_rules`) et
/// n'ont pas encore d'écran de réglage dédié.
class _ProposeSessionsDialog extends StatefulWidget {
  const _ProposeSessionsDialog({required this.planId});

  final String planId;

  @override
  State<_ProposeSessionsDialog> createState() =>
      _ProposeSessionsDialogState();
}

class _ProposeSessionsDialogState extends State<_ProposeSessionsDialog> {
  final _controller = TextEditingController(text: '30');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = int.tryParse(_controller.text.trim());
    final durationMin = (parsed != null && parsed > 0) ? parsed : 30;
    Navigator.of(context).pop(durationMin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: Key('treatment_plan_propose_sessions_dialog_${widget.planId}'),
      title: const Text('Proposer des séances'),
      content: NubiaTextField(
        key: Key('treatment_plan_default_duration_field_${widget.planId}'),
        variant: NubiaTextFieldVariant.numberStepper,
        controller: _controller,
        label: "Durée par défaut d'un acte (min)",
        min: 5,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        NubiaButton(
          key: Key('treatment_plan_propose_sessions_submit_${widget.planId}'),
          size: NubiaButtonSize.sm,
          icon: Icons.check,
          label: 'Proposer',
          onPressed: _submit,
        ),
      ],
    );
  }
}
