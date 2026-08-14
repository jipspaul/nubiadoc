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
              : _MessagingMasterDetail(
                  conversations: conversations,
                  selectedConversationId: null,
                  detail: null,
                ),
        PharmaMessagingThreadLoading(
          :final conversationId,
          :final conversations,
        ) =>
          _MessagingMasterDetail(
            conversations: conversations,
            selectedConversationId: conversationId,
            detail: const Center(
              key: Key('pharma_messaging_thread_loading'),
              child: CircularProgressIndicator(),
            ),
          ),
        PharmaMessagingThreadLoaded(
          :final conversation,
          :final conversations
        ) =>
          _MessagingMasterDetail(
            conversations: conversations,
            selectedConversationId: conversation.id,
            detail: _ThreadView(state: state),
          ),
        PharmaMessagingThreadError(
          :final conversationId,
          :final message,
          :final conversations
        ) =>
          _MessagingMasterDetail(
            conversations: conversations,
            selectedConversationId: conversationId,
            detail: NubiaErrorWidget(
              key: const Key('pharma_messaging_thread_error'),
              message: message,
              onRetry: () => context
                  .read<PharmaMessagingBloc>()
                  .add(const PharmaMessagingBackRequested()),
            ),
          ),
      },
    );
  }
}

// ---------------------------------------------------------------------------

/// Layout maître-détail (#4925) : sur poste comptoir (>= [_wideBreakpoint]),
/// la liste des conversations (344px, bordure droite `--n200`) et le fil
/// ouvert s'affichent côte à côte, coiffés par l'en-tête « Messages ».
/// En dessous du seuil, un seul volet à la fois — le fil remplace la liste,
/// comme côté patient.
class _MessagingMasterDetail extends StatelessWidget {
  const _MessagingMasterDetail({
    required this.conversations,
    required this.selectedConversationId,
    required this.detail,
  });

  static const _wideBreakpoint = 900.0;
  static const _listWidth = 344.0;

  final List<CabinetConversation> conversations;
  final String? selectedConversationId;
  final Widget? detail;

  @override
  Widget build(BuildContext context) {
    final unreadConversations =
        conversations.where((c) => c.unreadCount > 0).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _wideBreakpoint;
        final list = _ConversationsList(
          conversations: conversations,
          selectedConversationId: isWide ? selectedConversationId : null,
        );

        final Widget body;
        if (isWide) {
          body = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _listWidth,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(
                      right: BorderSide(color: NubiaColors.n200),
                    ),
                  ),
                  child: list,
                ),
              ),
              Expanded(
                child: detail ??
                    const NubiaEmptyState(
                      key: Key('pharma_messaging_no_selection'),
                      icon: Icons.forum_outlined,
                      title: 'Sélectionnez une conversation',
                      subtitle:
                          'Choisissez un patient dans la liste pour afficher le fil.',
                    ),
              ),
            ],
          );
        } else {
          body = detail ?? list;
        }

        return Column(
          children: [
            if (isWide || detail == null)
              _MessagingHeader(
                conversationCount: conversations.length,
                unreadCount: unreadConversations,
              ),
            Expanded(child: body),
          ],
        );
      },
    );
  }
}

/// En-tête « Messages · X conversations · Y non lues » coiffant les deux
/// volets sur poste comptoir (maquette design-v2).
class _MessagingHeader extends StatelessWidget {
  const _MessagingHeader({
    required this.conversationCount,
    required this.unreadCount,
  });

  final int conversationCount;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final conversationsLabel =
        conversationCount == 1 ? 'conversation' : 'conversations';
    final unreadLabel = unreadCount == 1 ? 'non lue' : 'non lues';

    return Container(
      key: const Key('pharma_messaging_header'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Text.rich(
        TextSpan(
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          children: [
            const TextSpan(text: 'Messages'),
            TextSpan(
              text:
                  ' · $conversationCount $conversationsLabel · $unreadCount $unreadLabel',
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.textTertiary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ConversationsList extends StatelessWidget {
  const _ConversationsList({
    required this.conversations,
    this.selectedConversationId,
  });

  final List<CabinetConversation> conversations;
  final String? selectedConversationId;

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
        final isSelected = conv.id == selectedConversationId;

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

        final row = ListRow(
          key: Key('conv_${conv.id}'),
          leading: NubiaAvatar(initials: _initials(conv.patientName)),
          title: conv.patientName,
          subtitleWidget: _ConversationSubtitle(
            subtitle: subtitle,
            unread: isUnread,
            orderRef: conv.orderRef,
            orderStatusLabel: conv.orderStatusLabel,
          ),
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

        if (!isSelected) return row;

        return DecoratedBox(
          decoration: const BoxDecoration(
            color: NubiaColors.brand50,
            border: Border(
              left: BorderSide(color: NubiaColors.brand700, width: 3),
            ),
          ),
          child: row,
        );
      },
    );
  }
}

/// Sous-titre d'une conversation : aperçu du dernier message puis, s'il y a
/// une commande liée, la rangée de tags commande + statut (#4923).
class _ConversationSubtitle extends StatelessWidget {
  const _ConversationSubtitle({
    required this.subtitle,
    required this.unread,
    required this.orderRef,
    required this.orderStatusLabel,
  });

  final String subtitle;
  final bool unread;
  final String? orderRef;
  final String? orderStatusLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodySmall?.copyWith(
            color: unread ? cs.onSurfaceVariant : tokens.textTertiary,
            fontWeight: unread ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
        if (orderRef != null) ...[
          const SizedBox(height: 4),
          _ConversationOrderTags(
            orderRef: orderRef!,
            orderStatusLabel: orderStatusLabel,
          ),
        ],
      ],
    );
  }
}

/// Rangée de tags commande sous une ligne de conversation : référence
/// commande (émeraude) + statut court (neutre).
class _ConversationOrderTags extends StatelessWidget {
  const _ConversationOrderTags({
    required this.orderRef,
    required this.orderStatusLabel,
  });

  final String orderRef;
  final String? orderStatusLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _OrderTag(
          label: orderRef,
          background: NubiaColors.brand50,
          foreground: NubiaColors.brand800,
          borderColor: NubiaColors.brand100,
          textTheme: textTheme,
        ),
        if (orderStatusLabel != null) ...[
          const SizedBox(width: 6),
          _OrderTag(
            label: orderStatusLabel!,
            background: NubiaColors.n100,
            foreground: NubiaColors.n600,
            textTheme: textTheme,
          ),
        ],
      ],
    );
  }
}

/// Pastille rectangulaire à coins peu arrondis (5px) du design v2, utilisée
/// pour les tags commande/statut — distincte de [NubiaBadge] (pill) et
/// [NubiaChip] (stadium).
class _OrderTag extends StatelessWidget {
  const _OrderTag({
    required this.label,
    required this.background,
    required this.foreground,
    required this.textTheme,
    this.borderColor,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color? borderColor;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(5),
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: Text(
        label,
        style: textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
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
    final order = message.attachedOrder;
    final isUrgent = message.urgency == MessageUrgency.urgent;
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
          border: isUrgent
              ? Border.all(color: NubiaColors.dangerBorder)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isUrgent) ...[
              const NubiaBadge.label(
                label: 'Urgent',
                variant: NubiaBadgeVariant.error,
              ),
              const SizedBox(height: 6),
            ],
            Text(
              message.text ?? '',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isCabinet ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: isCabinet ? Alignment.centerRight : Alignment.centerLeft,
              child: Text(
                _formatTimestamp(message.sentAt),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isCabinet
                          ? Colors.white.withOpacity(0.7)
                          : NubiaColors.n400,
                    ),
              ),
            ),
            if (order != null) ...[
              const SizedBox(height: 8),
              _OrderAttachmentCard(order: order, sent: isCabinet),
            ],
          ],
        ),
      ),
    );
  }
}

/// Carte commande jointe dans une bulle du fil (#4924) : icône, n° de
/// commande + nb de lignes, reste à payer. Surimpression claire dans une
/// bulle envoyée (émeraude), teinte `--brand50` dans une bulle reçue.
class _OrderAttachmentCard extends StatelessWidget {
  const _OrderAttachmentCard({required this.order, required this.sent});

  final MessageOrderAttachment order;
  final bool sent;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final background =
        sent ? Colors.white.withOpacity(0.16) : NubiaColors.brand50;
    final borderColor =
        sent ? Colors.white.withOpacity(0.3) : NubiaColors.brand100;
    final foreground = sent ? Colors.white : NubiaColors.brand800;
    final linesLabel =
        order.lineCount == 1 ? '1 ligne' : '${order.lineCount} lignes';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.inventory_2, size: 18, color: foreground),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${order.orderRef} · $linesLabel',
                  style: textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${CurrencyUtils.format(order.amountDueCents)} à régler au comptoir',
                  style: textTheme.labelSmall?.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ],
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
String _formatTimestamp(DateTime utc) {
  // #3856 : `dt` vient de DateTime.parse() sur un ISO avec offset +00:00→
  // isUtc == true. Lire .hour/.minute bruts affichait l'heure UTC au lieu
  // de l'heure locale (-2h en été/-1h en hiver pour Europe/Paris) ; la
  // comparaison sameDay confrontait aussi un instant UTC à un
  // DateTime.now() local, faussée autour de minuit.
  final dt = utc.toLocal();
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
