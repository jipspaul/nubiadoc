import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'messaging_bloc.dart';
import 'messaging_event.dart';
import 'messaging_state.dart';

/// Onglet "Messages" — liste des conversations + thread + envoi.
///
/// Consomme le [MessagingBloc] fourni par le parent (DashboardPage).
class MessagingPage extends StatelessWidget {
  const MessagingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _MessagingBody();
  }
}

// ---------------------------------------------------------------------------

class _MessagingBody extends StatelessWidget {
  const _MessagingBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MessagingBloc, MessagingState>(
      builder: (context, state) {
        if (state is MessagingInitial ||
            state is MessagingConversationsLoading) {
          return const Center(
            key: Key('messaging_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is MessagingConversationsError) {
          return NubiaErrorWidget(
            key: const Key('messaging_error'),
            message: state.message,
            onRetry: () => context
                .read<MessagingBloc>()
                .add(const MessagingConversationsLoadRequested()),
          );
        }
        if (state is MessagingConversationsLoaded) {
          if (state.conversations.isEmpty) {
            return const NubiaEmptyState(
              key: Key('messaging_empty'),
              icon: Icons.chat_bubble_outline,
              title: 'Aucun message',
              subtitle: 'Votre cabinet vous contactera ici.',
            );
          }
          return _ConversationsList(conversations: state.conversations);
        }
        if (state is MessagingThreadLoading) {
          return const Center(
            key: Key('messaging_thread_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is MessagingThreadLoaded) {
          return _ThreadView(state: state);
        }
        if (state is MessagingThreadError) {
          return NubiaErrorWidget(
            key: const Key('messaging_thread_error'),
            message: state.message,
            onRetry: () => context
                .read<MessagingBloc>()
                .add(const MessagingBackRequested()),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _ConversationsList extends StatelessWidget {
  const _ConversationsList({required this.conversations});

  final List<Conversation> conversations;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const Key('messaging_conversations_list'),
      itemCount: conversations.length,
      itemBuilder: (context, index) {
        final conv = conversations[index];
        final last = conv.lastMessage;
        // Le contrat liste (`GET /v1/conversations`) renvoie
        // `last_message_at` + `last_message_preview` (aperçu tronqué côté
        // serveur) ; fallback sur l'état non-lu pour les anciens payloads.
        final lastAt = conv.lastMessageAt ?? last?.sentAt;
        return ListRow(
          key: Key('conv_${conv.id}'),
          leading: NubiaAvatar(initials: _initials(conv.cabinetName)),
          title: conv.cabinetName,
          subtitle: _subtitle(
            conv.lastMessagePreview ?? last?.text,
            conv.unreadCount,
          ),
          unread: conv.unreadCount > 0,
          trailing: _Trailing(
            timestamp: lastAt != null ? _formatTimestamp(lastAt) : null,
            urgent: last?.urgency == MessageUrgency.urgent,
          ),
          onTap: () =>
              context.read<MessagingBloc>().add(MessagingThreadOpened(conv)),
        );
      },
    );
  }

  String _initials(String name) {
    final trimmed = name.trim();
    return trimmed.isNotEmpty ? trimmed.characters.first.toUpperCase() : '?';
  }

  /// Sous-titre affiché sous le nom du cabinet : aperçu du dernier message
  /// (`last_message_preview`) ; à défaut on résume l'état non-lu.
  String _subtitle(String? preview, int unreadCount) {
    if (preview != null && preview.trim().isNotEmpty) return preview.trim();
    if (unreadCount > 0) {
      return unreadCount == 1
          ? '1 nouveau message'
          : '$unreadCount nouveaux messages';
    }
    return 'Appuyez pour ouvrir la conversation';
  }

  String _formatTimestamp(DateTime utc) {
    // #3856 : `dt` vient de DateTime.parse() sur un ISO avec offset +00:00→
    // isUtc == true. Lire .hour/.minute bruts affichait l'heure UTC au lieu
    // de l'heure locale (-2h en été/-1h en hiver pour Europe/Paris) ; la
    // comparaison sameDay confrontait aussi un instant UTC à un
    // DateTime.now() local, faussée autour de minuit.
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
}

// ---------------------------------------------------------------------------

class _Trailing extends StatelessWidget {
  const _Trailing({required this.timestamp, required this.urgent});

  final String? timestamp;
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
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _ThreadView extends StatefulWidget {
  const _ThreadView({required this.state});

  final MessagingThreadLoaded state;

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
    context.read<MessagingBloc>().add(MessagingSendRequested(
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
        // Thread header with back button
        Material(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  key: const Key('messaging_back_button'),
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context
                      .read<MessagingBloc>()
                      .add(const MessagingBackRequested()),
                ),
                Expanded(
                  child: Text(
                    state.conversation.cabinetName.isNotEmpty
                        ? state.conversation.cabinetName
                        : 'Conversation',
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Messages list
        Expanded(
          child: state.messages.isEmpty
              ? const Center(
                  key: Key('messaging_thread_empty'),
                  child: Text('Aucun message dans cette conversation.'),
                )
              : ListView.builder(
                  key: const Key('messaging_thread_messages'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: state.messages.length,
                  itemBuilder: (context, i) =>
                      _MessageBubble(message: state.messages[i]),
                ),
        ),
        // Input bar
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('messaging_input'),
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
                      key: const Key('messaging_send_button'),
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
    final isPatient = message.sender == MessageSender.patient;
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: isPatient ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: isPatient ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.text ?? '',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isPatient ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}
