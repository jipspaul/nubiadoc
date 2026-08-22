import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/app_router.dart';
import 'messaging_bloc.dart';
import 'messaging_event.dart';
import 'messaging_state.dart';

/// Numéro du cabinet affiché dans la mention d'urgence sous le composeur
/// (#5284). [Conversation] n'expose aujourd'hui aucun numéro de téléphone
/// cabinet — constante à remplacer par une valeur issue du contrat
/// conversation/cabinet dès qu'un tel champ existera côté back.
const _kEmergencyCabinetPhone = '01 42 61 08 90';

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
          leading: _InterlocutorAvatar(type: conv.interlocutorType),
          title: conv.cabinetName,
          subtitle: _subtitle(
            conv.lastMessagePreview ?? last?.text,
            conv.unreadCount,
          ),
          unread: conv.unreadCount > 0,
          trailing: _Trailing(
            timestamp: lastAt != null ? NubiaDate.relative(lastAt) : null,
            urgent: last?.urgency == MessageUrgency.urgent,
          ),
          onTap: () =>
              context.read<MessagingBloc>().add(MessagingThreadOpened(conv)),
        );
      },
    );
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
}

// ---------------------------------------------------------------------------

/// Teinte bleue de la pharmacie, hors palette [NubiaColors] (verbatim
/// maquette design-v2, point 9 — même paire que la pastille pharmacie de
/// `notifications_page.dart`).
class _PharmacyColors {
  static const bg = Color(0xFFE0F2FE);
  static const fg = Color(0xFF0369A1);
}

/// Avatar carré arrondi de la liste des conversations (#5285) : pictogramme
/// et teinte distincts selon le type d'interlocuteur (cabinet vs pharmacie),
/// pour éviter la confusion entre les deux messageries (`pharma_messaging`
/// a son propre back-end).
class _InterlocutorAvatar extends StatelessWidget {
  const _InterlocutorAvatar({required this.type});

  final ConversationInterlocutorType type;

  @override
  Widget build(BuildContext context) {
    final isPharmacy = type == ConversationInterlocutorType.pharmacy;
    final background = isPharmacy ? _PharmacyColors.bg : NubiaColors.brand100;
    final foreground = isPharmacy ? _PharmacyColors.fg : NubiaColors.brand800;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        isPharmacy ? Icons.local_pharmacy : Icons.medical_services,
        color: foreground,
        size: 20,
      ),
    );
  }
}

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

  /// Réponse rapide (#5283) : pré-remplit puis envoie directement, sans
  /// passer par le clavier — la majorité des réponses patient tiennent en
  /// trois mots.
  void _sendQuickReply(String text) {
    _controller.text = text;
    _send();
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
        // Messages list — #4545 : `reverse: true` + index inversé plutôt
        // qu'un ScrollController piloté manuellement. La conversation
        // s'ouvre ainsi directement sur le dernier message (au lieu du
        // tout premier, historique), et reste ancrée en bas à chaque
        // nouveau message (envoyé ou reçu) sans code de scroll dédié — même
        // mécanisme que les listes de chat usuelles (WhatsApp, Slack…).
        Expanded(
          child: state.messages.isEmpty
              ? const Center(
                  key: Key('messaging_thread_empty'),
                  child: Text('Aucun message dans cette conversation.'),
                )
              : ListView.builder(
                  key: const Key('messaging_thread_messages'),
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: state.messages.length,
                  itemBuilder: (context, i) => _MessageBubble(
                    message: state.messages[state.messages.length - 1 - i],
                  ),
                ),
        ),
        // Input bar
        const Divider(height: 1),
        // Réponses rapides (#5283) : trois suggestions contextuelles
        // au-dessus du composeur, pour répondre sans ouvrir le clavier.
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              key: const Key('messaging_quick_replies'),
              children: [
                NubiaChip(
                  key: const Key('messaging_quick_reply_slot'),
                  label: 'Proposer un créneau',
                  icon: Icons.event_available,
                  onTap: state.sending
                      ? null
                      : () => _sendQuickReply('Proposer un créneau'),
                ),
                const SizedBox(width: 8),
                NubiaChip(
                  key: const Key('messaging_quick_reply_thanks'),
                  label: 'Merci !',
                  icon: Icons.check,
                  onTap:
                      state.sending ? null : () => _sendQuickReply('Merci !'),
                ),
                const SizedBox(width: 8),
                NubiaChip(
                  key: const Key('messaging_quick_reply_callback'),
                  label: 'Je rappelle',
                  icon: Icons.schedule,
                  onTap: state.sending
                      ? null
                      : () => _sendQuickReply('Je rappelle'),
                ),
              ],
            ),
          ),
        ),
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
                  : NubiaButton.icon(
                      key: const Key('messaging_send_button'),
                      icon: Icons.send,
                      onPressed: _send,
                    ),
            ],
          ),
        ),
        const _EmergencyNotice(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Mention obligatoire sous le composeur (#5284) : toute messagerie de santé
/// asynchrone doit rappeler qu'elle n'est pas un canal d'urgence, avec le
/// numéro à appeler — absence = risque, pas une omission de confort.
class _EmergencyNotice extends StatelessWidget {
  const _EmergencyNotice();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      key: const Key('messaging_emergency_notice'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: tokens.textTertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              "Cette messagerie n'est pas un service d'urgence. En cas de "
              'douleur aiguë ou de saignement, appelez le cabinet au '
              '$_kEmergencyCabinetPhone ou le 15.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: NubiaColors.n500,
                  ),
            ),
          ),
        ],
      ),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.text ?? '',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color:
                        isPatient ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  ),
            ),
            for (final attachment in message.attachments) ...[
              const SizedBox(height: 8),
              _AttachmentCard(attachment: attachment),
            ],
          ],
        ),
      ),
    );
  }
}

/// Carte pièce jointe cliquable liée au coffre documentaire (#5282) : icône +
/// titre + sous-ligne + chevron, tap → navigation vers le document dans la
/// feature `documents`. Tokens Nubia verbatim maquette design-v2 (point 6) :
/// fond `n50`, bordure `n200`, rayon 10px, icône émeraude.
class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({required this.attachment});

  final MessageAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      key: Key('messaging_attachment_${attachment.documentId}'),
      borderRadius: BorderRadius.circular(10),
      onTap: () => context
          .push('${AppRouter.documents}?id=${attachment.documentId}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: NubiaColors.n50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NubiaColors.n200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconFor(attachment.category),
              size: 18,
              color: NubiaColors.brand600,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    attachment.title,
                    style: textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (attachment.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      attachment.subtitle!,
                      style:
                          textTheme.labelSmall?.copyWith(color: NubiaColors.n500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: NubiaColors.n400),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(DocumentCategory category) {
    switch (category) {
      case DocumentCategory.quote:
        return Icons.request_quote_outlined;
      case DocumentCategory.invoice:
        return Icons.receipt_long_outlined;
      case DocumentCategory.prescription:
        return Icons.medication_outlined;
      case DocumentCategory.xray:
        return Icons.image_outlined;
      case DocumentCategory.cbct:
        return Icons.view_in_ar_outlined;
      case DocumentCategory.photo:
        return Icons.photo_camera_outlined;
      case DocumentCategory.report:
        return Icons.description_outlined;
      case DocumentCategory.consent:
        return Icons.verified_user_outlined;
      case DocumentCategory.instructions:
        return Icons.assignment_outlined;
      case DocumentCategory.mutualCard:
      case DocumentCategory.vitalCard:
        return Icons.badge_outlined;
      case DocumentCategory.other:
        return Icons.description_outlined;
    }
  }
}
