import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'cabinet_messaging_bloc.dart';
import 'cabinet_messaging_event.dart';
import 'cabinet_messaging_state.dart';
import 'widgets/appointment_slot_picker.dart';
import 'widgets/assignee_picker.dart';
import 'widgets/qualification_editor.dart';

const _statusLabels = {
  'open': 'Ouvert',
  'in_progress': 'En cours',
  'done': 'Traité',
  'closed': 'Fermé',
};

const _statusVariants = {
  'open': StatusPillVariant.warning,
  'in_progress': StatusPillVariant.progress,
  'done': StatusPillVariant.success,
  'closed': StatusPillVariant.neutral,
};

const _priorityLabels = {
  'low': 'Basse',
  'medium': 'Moyenne',
  'high': 'Haute',
  'urgent': 'Urgente',
};

const _priorityVariants = {
  'low': StatusPillVariant.neutral,
  'medium': StatusPillVariant.info,
  'high': StatusPillVariant.warning,
  'urgent': StatusPillVariant.error,
};

const _originLabels = {
  'phone': 'Téléphone',
  'app': 'Application',
  'web': 'Web',
  'email': 'E-mail',
  'other': 'Autre',
};

/// Résout le nom du praticien assigné à [conv] à partir du roster cabinet —
/// `assigneeUserId` peut aussi désigner un membre non-praticien (secrétaire),
/// d'où le libellé générique de repli plutôt qu'un blanc.
String _assigneeLabel(
  CabinetConversation conv,
  List<CabinetPractitioner> practitioners,
) {
  final id = conv.assigneeUserId;
  if (id == null) return 'Non assigné';
  for (final practitioner in practitioners) {
    if (practitioner.id == id) return practitioner.displayName;
  }
  return 'Assigné';
}

/// Écran "Messages" côté secrétariat — vue « Secrétariat » : tableau des
/// conversations qualifiées (statut, origine, synthèse, praticien, priorité,
/// date), filtres rapides, assignation, thread + passage en RDV (#7150).
/// Cloisonnement : aucun champ clinique (motif, notes médicales) affiché.
class CabinetMessagingPage extends StatefulWidget {
  const CabinetMessagingPage({super.key, this.openConversationId});

  /// Conversation à ouvrir dès que la liste est chargée — passée en `extra`
  /// depuis le ticket « Ouvrir » du tableau de bord secrétariat (#6246), pour
  /// cibler la conversation urgente plutôt que l'onglet « Tous » sans filtre.
  final String? openConversationId;

  @override
  State<CabinetMessagingPage> createState() => _CabinetMessagingPageState();
}

class _CabinetMessagingPageState extends State<CabinetMessagingPage> {
  bool _openConversationHandled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: BlocConsumer<CabinetMessagingBloc, CabinetMessagingState>(
        listener: (context, state) {
          if (state is CabinetMessagingThreadLoaded) {
            if (state.qualificationError != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.qualificationError!)),
              );
            }
            return;
          }
          if (state is! CabinetMessagingConversationsLoaded) return;
          if (state.assignError != null) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(state.assignError!)));
          }
          final targetId = widget.openConversationId;
          if (targetId == null || _openConversationHandled) return;
          _openConversationHandled = true;
          final matches =
              state.conversations.where((c) => c.id == targetId);
          if (matches.isNotEmpty) {
            context
                .read<CabinetMessagingBloc>()
                .add(CabinetMessagingThreadOpened(matches.first));
          }
        },
        builder: (context, state) => switch (state) {
          CabinetMessagingInitial() ||
          CabinetMessagingConversationsLoading() =>
            const Center(
              key: Key('cabinet_messaging_loading'),
              child: CircularProgressIndicator(),
            ),
          CabinetMessagingConversationsError(:final message) =>
            NubiaErrorWidget(
              key: const Key('cabinet_messaging_error'),
              message: message,
              onRetry: () => context.read<CabinetMessagingBloc>().add(
                    const CabinetMessagingConversationsLoadRequested(),
                  ),
            ),
          CabinetMessagingConversationsLoaded(
            :final conversations,
            :final practitioners,
          ) =>
            conversations.isEmpty
                ? const NubiaEmptyState(
                    key: Key('cabinet_messaging_empty'),
                    icon: Icons.chat_bubble_outline,
                    title: 'Aucune conversation',
                  )
                : _ConversationsList(
                    conversations: conversations,
                    practitioners: practitioners,
                    onRefresh: () async {
                      context.read<CabinetMessagingBloc>().add(
                            const CabinetMessagingConversationsLoadRequested(),
                          );
                    },
                  ),
          CabinetMessagingThreadLoading() => const Center(
              key: Key('cabinet_messaging_thread_loading'),
              child: CircularProgressIndicator(),
            ),
          final CabinetMessagingThreadLoaded s => _ThreadView(state: s),
          CabinetMessagingThreadError(:final message) => NubiaErrorWidget(
              key: const Key('cabinet_messaging_thread_error'),
              message: message,
              onRetry: () => context.read<CabinetMessagingBloc>().add(
                    const CabinetMessagingBackRequested(),
                  ),
            ),
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ConversationsList extends StatefulWidget {
  const _ConversationsList({
    required this.conversations,
    required this.practitioners,
    required this.onRefresh,
  });

  final List<CabinetConversation> conversations;
  final List<CabinetPractitioner> practitioners;
  final Future<void> Function() onRefresh;

  @override
  State<_ConversationsList> createState() => _ConversationsListState();
}

class _ConversationsListState extends State<_ConversationsList> {
  String _query = '';
  bool _showUnreadOnly = false;
  String? _statusFilter;
  String? _priorityFilter;
  String? _originFilter;

  Future<void> _assign(BuildContext context, CabinetConversation conv) async {
    final bloc = context.read<CabinetMessagingBloc>();
    final picked = await AssigneePicker.show(
      context,
      practitioners: widget.practitioners,
    );
    if (picked == null || !mounted) return;
    bloc.add(
      CabinetMessagingAssigneeChanged(
        conversationId: conv.id,
        assigneeUserId: picked.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.conversations
        .where(
          (c) => c.patientName.toLowerCase().contains(_query.toLowerCase()),
        )
        .where((c) => !_showUnreadOnly || c.unreadCount > 0)
        .where((c) => _statusFilter == null || c.status == _statusFilter)
        .where(
            (c) => _priorityFilter == null || c.priority == _priorityFilter)
        .where((c) => _originFilter == null || c.origin == _originFilter)
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            key: const Key('cabinet_messaging_search'),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Rechercher un patient',
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SegmentedButton<bool>(
            key: const Key('cabinet_messaging_filter'),
            segments: const [
              ButtonSegment<bool>(value: false, label: Text('Tous')),
              ButtonSegment<bool>(value: true, label: Text('Non lus')),
            ],
            selected: {_showUnreadOnly},
            onSelectionChanged: (s) =>
                setState(() => _showUnreadOnly = s.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FacetChipBar(
                keyPrefix: 'cabinet_messaging_status_facet',
                values: widget.conversations.map((c) => c.status),
                labels: _statusLabels,
                selected: _statusFilter,
                onSelected: (v) => setState(
                  () => _statusFilter = _statusFilter == v ? null : v,
                ),
              ),
              _FacetChipBar(
                keyPrefix: 'cabinet_messaging_priority_facet',
                values: widget.conversations
                    .map((c) => c.priority)
                    .whereType<String>(),
                labels: _priorityLabels,
                selected: _priorityFilter,
                onSelected: (v) => setState(
                  () => _priorityFilter = _priorityFilter == v ? null : v,
                ),
              ),
              _FacetChipBar(
                keyPrefix: 'cabinet_messaging_origin_facet',
                values: widget.conversations
                    .map((c) => c.origin)
                    .whereType<String>(),
                labels: _originLabels,
                selected: _originFilter,
                onSelected: (v) => setState(
                  () => _originFilter = _originFilter == v ? null : v,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            key: const Key('cabinet_messaging_refresh'),
            onRefresh: widget.onRefresh,
            child: ListView.builder(
              key: const Key('cabinet_messaging_conversations_list'),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final conv = filtered[index];
                final last = conv.lastMessage;
                return ListRow(
                  key: Key('conv_${conv.id}'),
                  leading: NubiaAvatar(initials: _initials(conv.patientName)),
                  title: conv.patientName,
                  subtitleWidget: _ConversationQualificationInfo(
                    conversation: conv,
                    lastMessageText: last?.text,
                    assigneeLabel:
                        _assigneeLabel(conv, widget.practitioners),
                    onAssign: () => _assign(context, conv),
                  ),
                  unread: conv.unreadCount > 0,
                  trailing: _ConversationTrailing(
                    timestamp: _formatTimestamp(
                      conv.lastMessageAt ?? last?.sentAt,
                    ),
                    unreadCount: conv.unreadCount,
                    urgent: conv.triageFlag == MessageUrgency.urgent,
                  ),
                  onTap: () => context.read<CabinetMessagingBloc>().add(
                        CabinetMessagingThreadOpened(conv),
                      ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Facettes de filtrage rapide (statut / priorité / origine) au-dessus de la
/// liste — même convention que `_StatusFacetBar` de l'écran Maintenance :
/// n'affiche que les valeurs réellement présentes dans [values], tap
/// bascule le filtre.
class _FacetChipBar extends StatelessWidget {
  const _FacetChipBar({
    required this.keyPrefix,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final String keyPrefix;
  final Iterable<String> values;
  final Map<String, String> labels;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final present =
        labels.keys.where((key) => values.contains(key)).toList();
    if (present.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final value in present) ...[
              ChoiceChip(
                key: Key('${keyPrefix}_$value'),
                label: Text(labels[value]!),
                selected: selected == value,
                onSelected: (_) => onSelected(value),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

/// Qualification d'une conversation (#7151/#7150) : dernier message, statut /
/// priorité / origine, synthèse et assignation — sous le titre de la ligne.
class _ConversationQualificationInfo extends StatelessWidget {
  const _ConversationQualificationInfo({
    required this.conversation,
    required this.lastMessageText,
    required this.assigneeLabel,
    required this.onAssign,
  });

  final CabinetConversation conversation;
  final String? lastMessageText;
  final String assigneeLabel;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final priority = conversation.priority;
    final origin = conversation.origin;
    final summary = conversation.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lastMessageText != null) ...[
          Text(
            lastMessageText!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: tokens.textTertiary),
          ),
          const SizedBox(height: 4),
        ],
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            StatusPill(
              label: _statusLabels[conversation.status] ?? conversation.status,
              variant:
                  _statusVariants[conversation.status] ??
                      StatusPillVariant.neutral,
            ),
            if (priority != null)
              StatusPill(
                label: _priorityLabels[priority] ?? priority,
                variant:
                    _priorityVariants[priority] ?? StatusPillVariant.neutral,
              ),
            if (origin != null)
              StatusPill(
                label: _originLabels[origin] ?? origin,
                variant: StatusPillVariant.info,
              ),
          ],
        ),
        if (summary != null && summary.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                assigneeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: tokens.textTertiary),
              ),
            ),
            TextButton(
              key: Key('assign_conversation_${conversation.id}'),
              onPressed: onAssign,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Assigner'),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

String _initials(String name) {
  final trimmed = name.trim();
  return trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
}

// #3857 (jumeau #3856) : l'entrée vient de DateTime.parse() sur un ISO avec
// offset +00:00 → isUtc == true. Lire .hour/.minute/.day bruts affichait
// l'heure UTC au lieu de l'heure locale (-2h été/-1h hiver Europe/Paris).
String? _formatTimestamp(DateTime? utc) {
  if (utc == null) return null;
  final dt = utc.toLocal();
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
  final now = DateTime.now();
  final sameDay =
      dt.year == now.year && dt.month == now.month && dt.day == now.day;
  if (sameDay) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
  return '${dt.day} ${months[dt.month - 1]}';
}

class _ConversationTrailing extends StatelessWidget {
  const _ConversationTrailing({
    required this.timestamp,
    required this.unreadCount,
    required this.urgent,
  });

  final String? timestamp;
  final int unreadCount;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (timestamp != null)
          Text(
            timestamp!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.textTertiary,
                ),
          ),
        if (urgent) ...[
          const SizedBox(height: 4),
          const NubiaBadge.label(
            label: 'Urgent',
            variant: NubiaBadgeVariant.error,
          ),
        ] else if (unreadCount > 0) ...[
          const SizedBox(height: 4),
          NubiaBadge.count(count: unreadCount),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _ThreadView extends StatefulWidget {
  const _ThreadView({required this.state});

  final CabinetMessagingThreadLoaded state;

  @override
  State<_ThreadView> createState() => _ThreadViewState();
}

class _ThreadViewState extends State<_ThreadView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    context.read<CabinetMessagingBloc>().add(
          CabinetMessagingSendRequested(
            conversationId: widget.state.conversation.id,
            text: text,
          ),
        );
    _controller.clear();
  }

  Future<void> _createAppointment() async {
    final slot = await AppointmentSlotPicker.show(context);
    if (slot == null || !mounted) return;
    context.read<CabinetMessagingBloc>().add(
          CabinetMessagingConvertToAppointmentRequested(
            conversationId: widget.state.conversation.id,
            slotId: slot.id,
          ),
        );
  }

  /// Ouvre l'éditeur de qualification du fil (#7609) — seule l'assignation
  /// était éditable jusqu'ici, depuis la liste.
  Future<void> _editQualification() async {
    final result = await QualificationEditor.show(
      context,
      conversation: widget.state.conversation,
    );
    if (result == null || !mounted) return;
    context.read<CabinetMessagingBloc>().add(
          CabinetMessagingQualificationChanged(
            conversationId: widget.state.conversation.id,
            origin: result.origin,
            priority: result.priority,
            status: result.status,
            summary: result.summary,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Material(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  key: const Key('cabinet_messaging_back_button'),
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Retour',
                  onPressed: () => context.read<CabinetMessagingBloc>().add(
                        const CabinetMessagingBackRequested(),
                      ),
                ),
                Expanded(
                  child: Text(
                    state.conversation.patientName.isNotEmpty
                        ? state.conversation.patientName
                        : 'Conversation',
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                state.qualifying
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : TextButton.icon(
                        key: const Key('edit_conversation_qualification'),
                        onPressed: _editQualification,
                        icon: const Icon(Icons.tune),
                        label: const Text('Qualifier'),
                      ),
                state.converting
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : TextButton.icon(
                        key: const Key('create_appointment_from_conversation'),
                        onPressed: _createAppointment,
                        icon: const Icon(Icons.event_available_outlined),
                        label: const Text('Créer un RDV'),
                      ),
              ],
            ),
          ),
        ),
        if (state.conversionError != null)
          Container(
            key: const Key('conversion_error_banner'),
            width: double.infinity,
            color: cs.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              state.conversionError!,
              style: TextStyle(color: cs.onErrorContainer),
            ),
          ),
        Expanded(
          child: state.messages.isEmpty
              ? const Center(
                  key: Key('cabinet_messaging_thread_empty'),
                  child: Text('Aucun message dans cette conversation.'),
                )
              : ListView.builder(
                  key: const Key('cabinet_messaging_thread_messages'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: state.messages.length,
                  itemBuilder: (context, i) =>
                      _MessageBubble(message: state.messages[i]),
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('cabinet_messaging_input'),
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Votre message…',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              state.sending
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      key: const Key('cabinet_messaging_send_button'),
                      icon: const Icon(Icons.send),
                      tooltip: 'Envoyer le message',
                      onPressed: _send,
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final isCabinet = message.sender == MessageSender.cabinet;
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: isCabinet ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: isCabinet ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.text ?? '',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isCabinet ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}
