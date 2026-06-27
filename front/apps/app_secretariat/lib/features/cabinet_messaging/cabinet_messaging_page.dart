import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'cabinet_messaging_bloc.dart';
import 'cabinet_messaging_event.dart';
import 'cabinet_messaging_state.dart';

/// Écran "Messages" côté secrétariat — liste des conversations patient + thread.
/// Cloisonnement : aucun champ clinique (motif, notes médicales) affiché.
class CabinetMessagingPage extends StatelessWidget {
  const CabinetMessagingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: BlocBuilder<CabinetMessagingBloc, CabinetMessagingState>(
        builder: (context, state) {
          if (state is CabinetMessagingInitial ||
              state is CabinetMessagingConversationsLoading) {
            return const Center(
              key: Key('cabinet_messaging_loading'),
              child: CircularProgressIndicator(),
            );
          }
          if (state is CabinetMessagingConversationsError) {
            return NubiaErrorWidget(
              key: const Key('cabinet_messaging_error'),
              message: state.message,
              onRetry: () => context.read<CabinetMessagingBloc>().add(
                const CabinetMessagingConversationsLoadRequested(),
              ),
            );
          }
          if (state is CabinetMessagingConversationsLoaded) {
            if (state.conversations.isEmpty) {
              return const NubiaEmptyState(
                key: Key('cabinet_messaging_empty'),
                icon: Icons.chat_bubble_outline,
                title: 'Aucune conversation',
              );
            }
            return _ConversationsList(
              conversations: state.conversations,
              onRefresh: () async {
                context.read<CabinetMessagingBloc>().add(
                      const CabinetMessagingConversationsLoadRequested(),
                    );
              },
            );
          }
          if (state is CabinetMessagingThreadLoading) {
            return const Center(
              key: Key('cabinet_messaging_thread_loading'),
              child: CircularProgressIndicator(),
            );
          }
          if (state is CabinetMessagingThreadLoaded) {
            return _ThreadView(state: state);
          }
          if (state is CabinetMessagingThreadError) {
            return NubiaErrorWidget(
              key: const Key('cabinet_messaging_thread_error'),
              message: state.message,
              onRetry: () => context.read<CabinetMessagingBloc>().add(
                const CabinetMessagingBackRequested(),
              ),
            );
          }
          return const SizedBox.shrink();
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
            child: ListView.separated(
              key: const Key('cabinet_messaging_conversations_list'),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final conv = filtered[index];
                return ListTile(
                  key: Key('conv_${conv.id}'),
                  leading: CircleAvatar(
                    child: Text(
                      conv.patientName.isNotEmpty
                          ? conv.patientName[0].toUpperCase()
                          : '?',
                    ),
                  ),
                  title: Text(conv.patientName),
                  subtitle: conv.lastMessage?.text != null
                      ? Text(
                          conv.lastMessage!.text!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  trailing: conv.unreadCount > 0
                      ? Badge(label: Text('${conv.unreadCount}'))
                      : null,
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

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
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
              ],
            ),
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
