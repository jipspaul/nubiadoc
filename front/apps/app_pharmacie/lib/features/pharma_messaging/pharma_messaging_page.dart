import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../orders/widgets/order_status_pill.dart';
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
      child: const PharmaMessagingView(),
    );
  }
}

// ---------------------------------------------------------------------------

/// Corps de l'écran « Messages » — consommable seul en test, en fournissant
/// un [PharmaMessagingBloc] via `BlocProvider.value` (miroir de `OrdersView`).
class PharmaMessagingView extends StatelessWidget {
  const PharmaMessagingView({super.key});

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
            detail: const _ThreadSkeleton(
              key: Key('pharma_messaging_thread_loading'),
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
            contextPanel: _ConversationContextPanel(state: state),
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
class _MessagingMasterDetail extends StatefulWidget {
  const _MessagingMasterDetail({
    required this.conversations,
    required this.selectedConversationId,
    required this.detail,
    this.contextPanel,
  });

  static const _wideBreakpoint = 900.0;
  static const _listWidth = 344.0;

  final List<CabinetConversation> conversations;
  final String? selectedConversationId;
  final Widget? detail;

  /// Colonne contexte (patient / commandes / horaires, #4926) — affichée
  /// uniquement quand un fil est ouvert (donc `null` pour les autres états).
  final Widget? contextPanel;

  @override
  State<_MessagingMasterDetail> createState() =>
      _MessagingMasterDetailState();
}

class _MessagingMasterDetailState extends State<_MessagingMasterDetail> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  _ConversationFacet _facet = _ConversationFacet.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conversations = widget.conversations;
    final unreadConversations =
        conversations.where((c) => c.unreadCount > 0).length;
    final urgentConversations = conversations
        .where((c) => c.triageFlag == MessageUrgency.urgent)
        .length;
    final searchFiltered = _filterConversations(conversations, _searchQuery);
    final filteredConversations = _filterByFacet(searchFiltered, _facet);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide =
            constraints.maxWidth >= _MessagingMasterDetail._wideBreakpoint;
        final list = Column(
          children: [
            _ConversationFacetBar(
              facet: _facet,
              allCount: conversations.length,
              unreadCount: unreadConversations,
              urgentCount: urgentConversations,
              onChanged: (facet) => setState(() => _facet = facet),
            ),
            Expanded(
              child: _ConversationsList(
                conversations: filteredConversations,
                selectedConversationId:
                    isWide ? widget.selectedConversationId : null,
              ),
            ),
          ],
        );

        final Widget body;
        if (isWide) {
          body = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _MessagingMasterDetail._listWidth,
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
                child: widget.detail ??
                    const NubiaEmptyState(
                      key: Key('pharma_messaging_no_selection'),
                      icon: Icons.forum_outlined,
                      title: 'Sélectionnez une conversation',
                      subtitle:
                          'Choisissez un patient dans la liste pour afficher le fil.',
                    ),
              ),
              if (widget.contextPanel != null) widget.contextPanel!,
            ],
          );
        } else {
          body = widget.detail ?? list;
        }

        return Column(
          children: [
            if (isWide || widget.detail == null)
              _MessagingHeader(
                conversationCount: conversations.length,
                unreadCount: unreadConversations,
                searchController: _searchController,
                onSearchChanged: (query) =>
                    setState(() => _searchQuery = query),
              ),
            Expanded(child: body),
          ],
        );
      },
    );
  }
}

/// Filtre les conversations sur le nom du patient ou la référence commande
/// (insensible à la casse) — agit uniquement sur l'affichage, la liste
/// chargée par le bloc reste intacte (#4931).
List<CabinetConversation> _filterConversations(
  List<CabinetConversation> conversations,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return conversations;
  return conversations.where((conv) {
    final matchesPatient = conv.patientName.toLowerCase().contains(q);
    final matchesOrder = conv.orderRef?.toLowerCase().contains(q) ?? false;
    return matchesPatient || matchesOrder;
  }).toList();
}

/// Facette de tri de la liste des conversations (#4932).
enum _ConversationFacet { all, unread, urgent }

/// Filtre les conversations selon la facette active. « Urgentes » se base
/// sur `triageFlag` (source de vérité de la liste, #3556) — pas sur
/// `lastMessage?.urgency`, propre au badge de rangée existant.
List<CabinetConversation> _filterByFacet(
  List<CabinetConversation> conversations,
  _ConversationFacet facet,
) {
  switch (facet) {
    case _ConversationFacet.all:
      return conversations;
    case _ConversationFacet.unread:
      return conversations.where((c) => c.unreadCount > 0).toList();
    case _ConversationFacet.urgent:
      return conversations
          .where((c) => c.triageFlag == MessageUrgency.urgent)
          .toList();
  }
}

/// Barre de facettes « Toutes / Non lues / Urgentes » coiffant la liste des
/// conversations (maquette design-v2, #4932) : une seule facette active à
/// la fois, chacune avec son compteur.
class _ConversationFacetBar extends StatelessWidget {
  const _ConversationFacetBar({
    required this.facet,
    required this.allCount,
    required this.unreadCount,
    required this.urgentCount,
    required this.onChanged,
  });

  final _ConversationFacet facet;
  final int allCount;
  final int unreadCount;
  final int urgentCount;
  final ValueChanged<_ConversationFacet> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('pharma_messaging_facets'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: NubiaColors.n200)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _FacetChip(
            value: _ConversationFacet.all,
            label: 'Toutes',
            count: allCount,
            selected: facet == _ConversationFacet.all,
            onChanged: onChanged,
          ),
          _FacetChip(
            value: _ConversationFacet.unread,
            label: 'Non lues',
            count: unreadCount,
            selected: facet == _ConversationFacet.unread,
            onChanged: onChanged,
          ),
          _FacetChip(
            value: _ConversationFacet.urgent,
            label: 'Urgentes',
            count: urgentCount,
            selected: facet == _ConversationFacet.urgent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Puce d'une facette : émeraude/stone du DS, ton sombre `n900` à l'état
/// actif (maquette design-v2, une seule facette active à la fois).
class _FacetChip extends StatelessWidget {
  const _FacetChip({
    required this.value,
    required this.label,
    required this.count,
    required this.selected,
    required this.onChanged,
  });

  final _ConversationFacet value;
  final String label;
  final int count;
  final bool selected;
  final ValueChanged<_ConversationFacet> onChanged;

  @override
  Widget build(BuildContext context) {
    return NubiaChip(
      key: Key('pharma_messaging_facet_${value.name}'),
      label: label,
      count: count,
      selected: selected,
      selectedBackground: NubiaColors.n900,
      selectedForeground: Colors.white,
      onTap: () => onChanged(value),
    );
  }
}

/// En-tête « Messages · X conversations · Y non lues » coiffant les deux
/// volets sur poste comptoir (maquette design-v2), avec le champ de
/// recherche des conversations (#4931) à droite.
class _MessagingHeader extends StatelessWidget {
  const _MessagingHeader({
    required this.conversationCount,
    required this.unreadCount,
    required this.searchController,
    required this.onSearchChanged,
  });

  final int conversationCount;
  final int unreadCount;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

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
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
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
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 240,
            child: TextField(
              key: const Key('pharma_messaging_search'),
              controller: searchController,
              onChanged: onSearchChanged,
              style: textTheme.bodySmall,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Patient, n° de commande…',
                prefixIcon: const Icon(Icons.search, size: 18),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 34, minHeight: 0),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: NubiaColors.n200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: NubiaColors.n200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: NubiaColors.brand700),
                ),
              ),
            ),
          ),
        ],
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

  void _insertQuickReply(String text) {
    _controller.text = text;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
  }

  void _attachOrder() {
    // TODO(#4930) : rattachement de commande — la pièce jointe commande
    // n'existe pas encore côté composer.
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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Wrap(
            key: const Key('pharma_messaging_quick_replies'),
            spacing: 8,
            runSpacing: 8,
            children: [
              NubiaChip(
                key: const Key('pharma_messaging_quick_reply_closing_time'),
                icon: Icons.schedule,
                label: 'Nous fermons à 19h30',
                onTap: () => _insertQuickReply('Nous fermons à 19h30'),
              ),
              NubiaChip(
                key: const Key('pharma_messaging_quick_reply_order_ready'),
                icon: Icons.inventory_2,
                label: 'Votre commande est prête',
                onTap: () => _insertQuickReply('Votre commande est prête'),
              ),
              NubiaChip(
                key: const Key('pharma_messaging_quick_reply_attach_order'),
                icon: Icons.link,
                label: 'Joindre la commande',
                onTap: _attachOrder,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: NubiaTextField(
                  key: const Key('pharma_messaging_input'),
                  controller: _controller,
                  variant: NubiaTextFieldVariant.multiline,
                  hint: 'Votre réponse…',
                  borderRadius: 12,
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                height: 44,
                child: state.sending
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton.filled(
                        key: const Key('pharma_messaging_send_button'),
                        style: IconButton.styleFrom(
                          backgroundColor: NubiaColors.brand700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.send),
                        onPressed: _send,
                      ),
              ),
            ],
          ),
        ),
        Padding(
          key: const Key('pharma_messaging_composer_hint'),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  '⏎ envoyer · ⇧⏎ nouvelle ligne',
                  overflow: TextOverflow.ellipsis,
                  style:
                      textTheme.bodySmall?.copyWith(color: tokens.textTertiary),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 14,
                      color: tokens.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Aucun conseil médical par écrit',
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall
                            ?.copyWith(color: tokens.textTertiary),
                      ),
                    ),
                  ],
                ),
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

/// Colonne de contexte (aside droite, 288px) affichée à côté du fil ouvert :
/// identité patient, commandes passées, horaires du jour de l'officine
/// (#4926). Purement organisationnel — aucune donnée médicale/diagnostic.
class _ConversationContextPanel extends StatelessWidget {
  const _ConversationContextPanel({required this.state});

  static const _width = 288.0;

  final PharmaMessagingThreadLoaded state;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    return SizedBox(
      key: const Key('pharma_messaging_context_panel'),
      width: _width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: tokens.borderSubtle)),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _PatientSection(conversation: state.conversation),
            const SizedBox(height: 20),
            _OrdersSection(orders: state.patientOrders),
            const SizedBox(height: 20),
            const _HoursSection(),
            const SizedBox(height: 20),
            const _ComplianceNote(),
          ],
        ),
      ),
    );
  }
}

/// En-tête de section de la colonne contexte : icône + titre, badge de
/// total optionnel à droite (ex. nombre de commandes).
class _ContextSectionHeader extends StatelessWidget {
  const _ContextSectionHeader({
    required this.icon,
    required this.title,
    this.badgeCount,
  });

  final IconData icon;
  final String title;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(icon, size: 16, color: tokens.textTertiary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style:
                textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (badgeCount != null) NubiaBadge.count(count: badgeCount!),
      ],
    );
  }
}

/// Ligne clé/valeur (« Nom : Julie Martin ») — valeur en tabular-nums quand
/// [tabularNums] (numéros, horaires).
class _ContextKeyValueRow extends StatelessWidget {
  const _ContextKeyValueRow({
    required this.label,
    required this.value,
    this.tabularNums = false,
  });

  final String label;
  final String value;
  final bool tabularNums;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text.rich(
        TextSpan(
          style: textTheme.bodySmall?.copyWith(color: tokens.textTertiary),
          children: [
            TextSpan(text: '$label : '),
            TextSpan(
              text: value,
              style: textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontFeatures: tabularNums
                    ? const [FontFeature.tabularFigures()]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section « Patiente » : nom, téléphone (tabular-nums), officine.
class _PatientSection extends StatelessWidget {
  const _PatientSection({required this.conversation});

  final CabinetConversation conversation;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('pharma_messaging_ctx_patient'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ContextSectionHeader(icon: Icons.person, title: 'Patiente'),
        _ContextKeyValueRow(label: 'Nom', value: conversation.patientName),
        _ContextKeyValueRow(
          label: 'Téléphone',
          value: conversation.patientPhone ?? '—',
          tabularNums: true,
        ),
        // « Titulaire ici » : cette colonne ne sert que le contexte de
        // l'officine en cours, pas un choix multi-pharmacie (#4926).
        const _ContextKeyValueRow(label: 'Pharmacie', value: 'Titulaire ici'),
      ],
    );
  }
}

/// Section « Commandes » : historique des commandes du patient, badge total
/// dans l'en-tête, pastille de statut par ligne.
class _OrdersSection extends StatelessWidget {
  const _OrdersSection({required this.orders});

  final List<PharmacyOrder> orders;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    return Column(
      key: const Key('pharma_messaging_ctx_orders'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ContextSectionHeader(
          icon: Icons.receipt_long,
          title: 'Commandes',
          badgeCount: orders.length,
        ),
        if (orders.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Aucune commande',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: tokens.textTertiary),
            ),
          )
        else
          for (final order in orders) _OrderContextRow(order: order),
      ],
    );
  }
}

/// Une commande dans la section « Commandes » : n°, sous-ligne jour +
/// nombre de lignes, pastille de statut.
class _OrderContextRow extends StatelessWidget {
  const _OrderContextRow({required this.order});

  final PharmacyOrder order;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    // Fallback dérivé de l'id réel tant que `order_ref` n'est pas exposé
    // par le contrat back (#4926) — jamais de donnée inventée. On prend au
    // plus 4 caractères (les id courts, ex. « o1 » en test, sont plus courts
    // que 4 → pas de RangeError sur substring).
    final rawId = order.id.replaceAll('-', '');
    final ref = order.orderRef ??
        'CMD-${rawId.substring(0, rawId.length < 4 ? rawId.length : 4).toUpperCase()}';
    final lines = order.lineCount;
    final day = _relativeDay(order.createdAt);
    final subtitle =
        lines == null ? day : '$day · $lines ${lines >= 2 ? 'lignes' : 'ligne'}';

    return Padding(
      key: Key('pharma_messaging_ctx_order_${order.id}'),
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 16, color: tokens.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ref,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  subtitle,
                  style: textTheme.labelSmall
                      ?.copyWith(color: tokens.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OrderStatusPill(status: order.status),
        ],
      ),
    );
  }
}

/// Section « Horaires aujourd'hui ». Pas de contrat back pour les horaires
/// d'officine à ce jour (#4926, cf. issue : « à créer ») — contenu fixe en
/// attendant, comme autorisé au stade POC (`AGENTS.md` racine).
class _HoursSection extends StatelessWidget {
  const _HoursSection();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      key: const Key('pharma_messaging_ctx_hours'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ContextSectionHeader(
          icon: Icons.local_pharmacy,
          title: "Horaires aujourd'hui",
        ),
        const _ContextKeyValueRow(
          label: 'Ouverture',
          value: '08:30 – 19:30',
          tabularNums: true,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text.rich(
            TextSpan(
              style:
                  textTheme.bodySmall?.copyWith(color: tokens.textTertiary),
              children: [
                const TextSpan(text: 'Actuellement : '),
                TextSpan(
                  text: 'Ouvert',
                  style: TextStyle(
                    color: tokens.successFg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Note de cadrage réglementaire en bas de colonne : cette messagerie sert
/// l'organisation d'une délivrance, jamais le conseil pharmaceutique.
class _ComplianceNote extends StatelessWidget {
  const _ComplianceNote();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      key: const Key('pharma_messaging_ctx_note'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.infoBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield, size: 16, color: tokens.infoFg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Cette messagerie sert à l'organisation d'une délivrance : "
              'disponibilité, horaires, substitution. Un conseil '
              'pharmaceutique se donne au comptoir ou par téléphone.',
              style: textTheme.labelSmall?.copyWith(color: tokens.infoFg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Jour relatif court (« Aujourd'hui », « Hier » ou `jj/MM`) pour la
/// sous-ligne des commandes de la colonne contexte.
String _relativeDay(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return "Aujourd'hui";
  if (diff == 1) return 'Hier';
  return '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}';
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

/// Squelette de chargement du fil : bulles alternées gauche/droite,
/// cohérent avec [_ConversationsSkeleton] (#4934).
class _ThreadSkeleton extends StatelessWidget {
  const _ThreadSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      children: [
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Align(
              alignment:
                  i.isEven ? Alignment.centerLeft : Alignment.centerRight,
              child: NubiaSkeletonLoader(
                width: 180 + (i % 3) * 40,
                height: 40,
                borderRadius: 16,
              ),
            ),
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
