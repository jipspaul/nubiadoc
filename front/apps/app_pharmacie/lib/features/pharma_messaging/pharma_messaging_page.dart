import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'pharma_messaging_bloc.dart';
import 'pharma_messaging_event.dart';
import 'pharma_messaging_state.dart';

/// Écran "Messages" côté pharmacien — liste des conversations patient + thread.
class PharmaMessagingPage extends StatelessWidget {
  const PharmaMessagingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<PharmaMessagingBloc>()
        ..add(const PharmaMessagingConversationsLoadRequested()),
      child: const _PharmaMessagingBody(),
    );
  }
}

// ---------------------------------------------------------------------------

class _PharmaMessagingBody extends StatelessWidget {
  const _PharmaMessagingBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PharmaMessagingBloc, PharmaMessagingState>(
      builder: (context, state) => switch (state) {
        PharmaMessagingInitial() ||
        PharmaMessagingConversationsLoading() =>
          const _ConversationsSkeleton(key: Key('pharma_messaging_loading')),
        PharmaMessagingConversationsError(:final message) => NubiaErrorWidget(
            key: const Key('pharma_messaging_error'),
            message: message,
            onRetry: () => context.read<PharmaMessagingBloc>().add(
                  const PharmaMessagingConversationsLoadRequested(),
                ),
          ),
        PharmaMessagingConversationsLoaded(:final conversations) =>
          conversations.isEmpty
              ? const NubiaEmptyState(
                  key: Key('pharma_messaging_empty'),
                  icon: Icons.chat_bubble_outline,
                  title: 'Aucun message',
                  subtitle: 'Vos conversations patients apparaîtront ici',
                )
              : _ConversationsList(conversations: conversations),
        PharmaMessagingThreadLoading() => const Center(
            key: Key('pharma_messaging_thread_loading'),
            child: CircularProgressIndicator(),
          ),
        PharmaMessagingThreadLoaded() => _ThreadView(state: state),
        PharmaMessagingThreadError(:final message) => NubiaErrorWidget(
            key: const Key('pharma_messaging_thread_error'),
            message: message,
            onRetry: () => context
                .read<PharmaMessagingBloc>()
                .add(const PharmaMessagingBackRequested()),
          ),
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _ConversationsList extends StatelessWidget {
  const _ConversationsList({required this.conversations});

  final List<CabinetConversation> conversations;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const Key('pharma_messaging_conversations_list'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: conversations.length,
      itemBuilder: (context, index) {
        final conv = conversations[index];
        final isUnread = conv.unreadCount > 0;
        final isUrgent = conv.lastMessage?.urgency == MessageUrgency.urgent;
        final timestamp = conv.lastMessageAt ?? conv.lastMessage?.sentAt;

        // #3854 : GET /pharmacy/conversations n'a jamais émis `last_message`
        // (objet imbriqué) — seul `last_message_preview` (string) est réel,
        // comme côté cabinet (#3373). Lire uniquement `lastMessage?.text`
        // affichait « Aucun message » sur TOUT fil, y compris avec des
        // non-lus.
        final subtitle = conv.lastMessagePreview ??
            conv.lastMessage?.text ??
            (isUnread
                ? '${conv.unreadCount} message(s) non lu(s)'
                : 'Aucun message');

        return ListRow(
          key: Key('conv_${conv.id}'),
          leading: NubiaAvatar(initials: _initials(conv.patientName)),
          title: conv.patientName,
          subtitle: subtitle,
          unread: isUnread,
          showDivider: index != conversations.length - 1,
          trailing: _ConversationTrailing(
            timestamp: timestamp,
            unreadCount: conv.unreadCount,
            isUrgent: isUrgent,
          ),
          onTap: () => context
              .read<PharmaMessagingBloc>()
              .add(PharmaMessagingThreadOpened(conv)),
        );
      },
    );
  }
}

/// Métadonnées à droite d'une conversation : horodatage + badges urgent/non-lu.
class _ConversationTrailing extends StatelessWidget {
  const _ConversationTrailing({
    required this.timestamp,
    required this.unreadCount,
    required this.isUrgent,
  });

  final DateTime? timestamp;
  final int unreadCount;
  final bool isUrgent;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (timestamp != null)
          Text(
            _formatTimestamp(timestamp!),
            style: textTheme.labelSmall?.copyWith(color: tokens.textTertiary),
          ),
        if (isUrgent || unreadCount > 0) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isUrgent) ...[
                const NubiaBadge.label(
                  label: 'Urgent',
                  variant: NubiaBadgeVariant.error,
                ),
                if (unreadCount > 0) const SizedBox(width: 6),
              ],
              if (unreadCount > 0) NubiaBadge.count(count: unreadCount),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _ThreadView extends StatefulWidget {
  const _ThreadView({required this.state});

  final PharmaMessagingThreadLoaded state;

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
    context.read<PharmaMessagingBloc>().add(PharmaMessagingSendRequested(
          conversationId: widget.state.conversation.id,
          text: text,
        ));
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final name = state.conversation.patientName.isNotEmpty
        ? state.conversation.patientName
        : 'Conversation';

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(
              bottom: BorderSide(color: tokens.borderSubtle),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              IconButton(
                key: const Key('pharma_messaging_back_button'),
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context
                    .read<PharmaMessagingBloc>()
                    .add(const PharmaMessagingBackRequested()),
              ),
              NubiaAvatar(initials: _initials(name), radius: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: state.messages.isEmpty
              ? const NubiaEmptyState(
                  key: Key('pharma_messaging_thread_empty'),
                  icon: Icons.forum_outlined,
                  title: 'Aucun message',
                  subtitle: 'Démarrez la conversation ci-dessous.',
                )
              : ListView.builder(
                  key: const Key('pharma_messaging_thread_messages'),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: state.messages.length,
                  itemBuilder: (context, i) =>
                      _MessageBubble(message: state.messages[i]),
                ),
        ),
        Divider(height: 1, color: tokens.borderSubtle),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('pharma_messaging_input'),
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Votre message…',
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
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
                  : IconButton.filled(
                      key: const Key('pharma_messaging_send_button'),
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
    // Cabinet = officine (right), patient = left
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

/// Squelette de chargement de la liste des conversations.
class _ConversationsSkeleton extends StatelessWidget {
  const _ConversationsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < 8; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: NubiaSkeletonLoader(height: 56, borderRadius: 12),
          ),
      ],
    );
  }
}

/// Horodatage court : `HH:mm` si aujourd'hui, sinon `jj/MM`.
String _formatTimestamp(DateTime dt) {
  final now = DateTime.now();
  final isToday =
      dt.year == now.year && dt.month == now.month && dt.day == now.day;
  if (isToday) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
  return '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}';
}

/// Initiales (max 2 lettres) à partir d'un nom complet.
String _initials(String fullName) {
  final parts =
      fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}
