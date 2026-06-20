import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
    return BlocBuilder<CabinetMessagingBloc, CabinetMessagingState>(
      builder: (context, state) {
        if (state is CabinetMessagingInitial ||
            state is CabinetMessagingConversationsLoading) {
          return const Center(
            key: Key('cabinet_messaging_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is CabinetMessagingConversationsError) {
          return _ErrorView(
            key: const Key('cabinet_messaging_error'),
            message: state.message,
            onRetry: () => context.read<CabinetMessagingBloc>().add(
                  const CabinetMessagingConversationsLoadRequested(),
                ),
          );
        }
        if (state is CabinetMessagingConversationsLoaded) {
          if (state.conversations.isEmpty) {
            return const Center(
              key: Key('cabinet_messaging_empty'),
              child: _EmptyConversations(),
            );
          }
          return _ConversationsList(conversations: state.conversations);
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
          return _ErrorView(
            key: const Key('cabinet_messaging_thread_error'),
            message: state.message,
            onRetry: () => context
                .read<CabinetMessagingBloc>()
                .add(const CabinetMessagingBackRequested()),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _EmptyConversations extends StatelessWidget {
  const _EmptyConversations();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.chat_bubble_outline,
          size: 56,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          'Aucun message',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _ConversationsList extends StatefulWidget {
  const _ConversationsList({required this.conversations});

  final List<CabinetConversation> conversations;

  @override
  State<_ConversationsList> createState() => _ConversationsListState();
}

class _ConversationsListState extends State<_ConversationsList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.conversations
        .where((c) =>
            c.patientName.toLowerCase().contains(_query.toLowerCase()))
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
        Expanded(
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
                onTap: () => context
                    .read<CabinetMessagingBloc>()
                    .add(CabinetMessagingThreadOpened(conv)),
              );
            },
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
    context.read<CabinetMessagingBloc>().add(CabinetMessagingSendRequested(
          conversationId: widget.state.conversation.id,
          text: text,
        ));
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
                  onPressed: () => context
                      .read<CabinetMessagingBloc>()
                      .add(const CabinetMessagingBackRequested()),
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
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}
