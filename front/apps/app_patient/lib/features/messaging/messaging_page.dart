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
            onRetry: () => context.pop(),
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
          onTap: () => context.push(
            '${AppRouter.messaging}/${conv.id}',
            extra: conv,
          ),
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
                  onPressed: () => context.pop(),
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
              : Builder(
                  builder: (context) {
                    final items = _threadItemsFor(state.messages);
                    return ListView.builder(
                      key: const Key('messaging_thread_messages'),
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final item = items[items.length - 1 - i];
                        return switch (item) {
                          _DaySeparator() => _DaySeparatorLabel(day: item.day),
                          _MessageItem() => _MessageBubble(message: item.message),
                        };
                      },
                    );
                  },
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
                child: NubiaTextField(
                  key: const Key('messaging_input'),
                  controller: _controller,
                  hint: 'Votre message…',
                  borderRadius: 21,
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

/// Élément affiché dans le fil : soit un message, soit un séparateur de jour
/// inséré devant le premier message d'une journée distincte (#5278).
sealed class _ThreadItem {
  const _ThreadItem();
}

class _MessageItem extends _ThreadItem {
  const _MessageItem(this.message);

  final Message message;
}

class _DaySeparator extends _ThreadItem {
  const _DaySeparator(this.day);

  final DateTime day;
}

/// Intercale un [_DaySeparator] devant le premier message de chaque journée
/// distincte (comparaison `NubiaDate.isSameDay`, heure locale — #3856).
/// [messages] est en ordre chronologique croissant (le plus ancien en index
/// 0), comme consommé par `ListView.builder(reverse: true)` (#4545).
List<_ThreadItem> _threadItemsFor(List<Message> messages) {
  final items = <_ThreadItem>[];
  DateTime? previousDay;
  for (final message in messages) {
    if (previousDay == null || !NubiaDate.isSameDay(previousDay, message.sentAt)) {
      items.add(_DaySeparator(message.sentAt));
      previousDay = message.sentAt;
    }
    items.add(_MessageItem(message));
  }
  return items;
}

/// Séparateur de jour du fil (#5278) : libellé centré, gris `n400`, poids
/// 600, ~11px, verbatim maquette design-v2 (point 3) — évite qu'un fil de
/// plusieurs mois soit « un mur indifférencié ».
class _DaySeparatorLabel extends StatelessWidget {
  const _DaySeparatorLabel({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          NubiaDate.daySeparatorLabel(day),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: tokens.textTertiary,
          ),
        ),
      ),
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
    final isUrgent = message.urgency == MessageUrgency.urgent;
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Align(
      alignment: isPatient ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: isUrgent
              ? tokens.dangerBg
              : isPatient
                  ? cs.primaryContainer
                  : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border:
              isUrgent ? Border.all(color: NubiaColors.dangerBorder) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isUrgent) ...[
              _UrgentBanner(color: tokens.dangerFg),
              const SizedBox(height: 6),
            ],
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
            const SizedBox(height: 4),
            _MessageMeta(
              time: _formatMessageTime(message.sentAt),
              isPatient: isPatient,
              read: message.readAt != null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bandeau d'urgence porté par la bulle (#5276), verbatim maquette design-v2
/// (point 2) : `MessageUrgency` ne doit pas exister uniquement dans la liste
/// (`_Trailing.urgent`) — sinon ouvrir la conversation fait disparaître le
/// signal qui a fait cliquer, et un message urgent ancien dans l'historique
/// n'est jamais signalé. Même teinte que `NubiaBadgeVariant.error`.
class _UrgentBanner extends StatelessWidget {
  const _UrgentBanner({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.priority_high, size: 13, color: color),
        const SizedBox(width: 2),
        Text(
          'URGENT',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Heure d'envoi au format `HH:MM` (#5277), toujours convertie via
/// `.toLocal()` avant de lire heure/minute — évite le piège UTC #3856
/// (le séparateur de jour couvrant déjà la date, la meta ne montre que
/// l'heure, contrairement à `NubiaDate.relative` qui bascule sur
/// `<jour> <mois>` au-delà du jour courant).
String _formatMessageTime(DateTime sentAt) {
  final local = sentAt.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Ligne meta en pied de bulle (#5277) : heure d'envoi ~10.5px, verbatim
/// maquette design-v2 (point 3). Sur une bulle patient lue (`readAt` non
/// nul), un accusé de lecture `done_all` accompagne l'heure ; sur une bulle
/// reçue, l'heure seule en gris `n400`.
class _MessageMeta extends StatelessWidget {
  const _MessageMeta({
    required this.time,
    required this.isPatient,
    required this.read,
  });

  final String time;
  final bool isPatient;
  final bool read;

  @override
  Widget build(BuildContext context) {
    final color = isPatient
        ? Theme.of(context)
            .colorScheme
            .onPrimaryContainer
            .withValues(alpha: 0.7)
        : NubiaColors.n400;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(time, style: TextStyle(fontSize: 10.5, color: color)),
        if (isPatient && read) ...[
          const SizedBox(width: 4),
          Icon(Icons.done_all, size: 13, color: color),
        ],
      ],
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
