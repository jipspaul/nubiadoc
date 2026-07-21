import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'cabinet_messaging_bloc.dart';
import 'cabinet_messaging_event.dart';
import 'cabinet_messaging_state.dart';
import 'widgets/appointment_slot_picker.dart';

/// Écran "Messages" côté secrétariat — liste des conversations patient + thread.
/// Cloisonnement : aucun champ clinique (motif, notes médicales) affiché.
class CabinetMessagingPage extends StatelessWidget {
  const CabinetMessagingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: BlocBuilder<CabinetMessagingBloc, CabinetMessagingState>(
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
          CabinetMessagingConversationsLoaded(:final conversations) =>
            conversations.isEmpty
                ? const NubiaEmptyState(
                    key: Key('cabinet_messaging_empty'),
                    icon: Icons.chat_bubble_outline,
                    title: 'Aucune conversation',
                  )
                : _ConversationsList(
                    conversations: conversations,
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
    required this.onRefresh,
  });

  final List<CabinetConversation> conversations;
  final Future<void> Function() onRefresh;

  @override
  State<_ConversationsList> createState() => _ConversationsListState();
}

class _ConversationsListState extends State<_ConversationsList> {
  String _query = '';
  bool _showUnreadOnly = false;

  @override
  Widget build(BuildContext context) {
    final filtered = widget.conversations
        .where(
          (c) => c.patientName.toLowerCase().contains(_query.toLowerCase()),
        )
        .where((c) => !_showUnreadOnly || c.unreadCount > 0)
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
                  subtitle: last?.text,
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
