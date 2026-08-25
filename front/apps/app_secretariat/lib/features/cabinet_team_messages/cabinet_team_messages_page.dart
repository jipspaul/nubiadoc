//! Écran de messagerie interne d'équipe (#4156) — fil unique du cabinet,
//! staff↔staff, distinct de la messagerie patient (cabinet_messaging).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'cabinet_team_messages_cubit.dart';

class CabinetTeamMessagesPage extends StatelessWidget {
  const CabinetTeamMessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => CabinetTeamMessagesCubit(
        listMessages: GetIt.instance<ListCabinetTeamMessagesUseCase>(),
        sendMessage: GetIt.instance<SendCabinetTeamMessageUseCase>(),
      ),
      child: const _TeamMessagesScaffold(),
    );
  }
}

/// Porte la requête de recherche du fil (#5132) : pas d'état cubit dédié, le
/// fil est court (cf. docstring cubit) donc un filtrage local suffit et
/// laisse `CabinetTeamMessagesLoaded` inchangé quand la recherche est vide.
class _TeamMessagesScaffold extends StatefulWidget {
  const _TeamMessagesScaffold();

  @override
  State<_TeamMessagesScaffold> createState() => _TeamMessagesScaffoldState();
}

class _TeamMessagesScaffoldState extends State<_TeamMessagesScaffold> {
  String _searchQuery = '';

  void _onSearchChanged(String value) => setState(() => _searchQuery = value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _TeamMessagesAppBar(onSearchChanged: _onSearchChanged),
      body: _TeamMessagesBody(searchQuery: _searchQuery),
    );
  }
}

class _TeamMessagesAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _TeamMessagesAppBar({required this.onSearchChanged});

  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) => AppBar(
        title: const Text('Messagerie interne'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SizedBox(
              width: 230,
              child: NubiaSearchBar(
                key: const Key('team_messages_search'),
                hint: 'Rechercher dans le fil…',
                onChanged: onSearchChanged,
              ),
            ),
          ),
        ],
      );

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _TeamMessagesBody extends StatefulWidget {
  const _TeamMessagesBody({required this.searchQuery});

  final String searchQuery;

  @override
  State<_TeamMessagesBody> createState() => _TeamMessagesBodyState();
}

class _TeamMessagesBodyState extends State<_TeamMessagesBody> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send(BuildContext context) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    context.read<CabinetTeamMessagesCubit>().send(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CabinetTeamMessagesCubit, CabinetTeamMessagesState>(
      listenWhen: (_, curr) =>
          curr is CabinetTeamMessagesLoaded && curr.sendError != null,
      listener: (context, state) {
        if (state is CabinetTeamMessagesLoaded && state.sendError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.sendError!)),
          );
        }
      },
      builder: (context, state) {
        final thread = Column(
          children: [
            Expanded(
              child: switch (state) {
                CabinetTeamMessagesLoading() =>
                  const _MessagesSkeleton(key: Key('team_messages_loading')),
                CabinetTeamMessagesError(:final message) => NubiaErrorWidget(
                    key: const Key('team_messages_error'),
                    message: message,
                    onRetry: () =>
                        context.read<CabinetTeamMessagesCubit>().load(),
                  ),
                CabinetTeamMessagesLoaded(:final messages) => _MessagesList(
                    messages: _filterMessages(messages, widget.searchQuery),
                    isSearching: widget.searchQuery.trim().isNotEmpty,
                  ),
              },
            ),
            _Composer(
              controller: _controller,
              enabled: state is CabinetTeamMessagesLoaded && !state.sending,
              onSend: () => _send(context),
            ),
          ],
        );
        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 900) return thread;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: thread),
                const _TeamAside(),
              ],
            );
          },
        );
      },
    );
  }
}

/// Membre du panneau « Équipe » (#5133) : roster + présence du cabinet,
/// visible en colonne latérale sur desktop pour savoir depuis le comptoir
/// qui est disponible. Données fictives verbatim de la maquette design-v2 en
/// attendant une API de présence dédiée (aucune ne réunit aujourd'hui tous
/// les rôles du cabinet sans restriction admin, cf. `MembersAccessCubit`).
class _TeamMember {
  const _TeamMember({
    required this.name,
    required this.subtitle,
    required this.initials,
    required this.present,
  });

  final String name;
  final String subtitle;
  final String initials;
  final bool present;
}

/// Ligne du récap « Éléments cités aujourd'hui » (#5131) : objets produit
/// référencés dans le fil du jour, verbatim de la maquette design-v2.
/// Données fictives en attendant que le fil expose vraiment `reference`
/// (même limite que [_TeamMember] ci-dessus : pas d'agrégat serveur dédié).
class _CitedReference {
  const _CitedReference({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

const _citedReferencesToday = [
  _CitedReference(
    icon: Icons.precision_manufacturing,
    title: 'Couronne · dent 26',
    subtitle: 'Travaux labo',
  ),
  _CitedReference(
    icon: Icons.inventory_2,
    title: 'Demande de stock',
    subtitle: 'Pharmacie du Théâtre',
  ),
];

const _teamMembers = [
  _TeamMember(
    name: 'Sarah Lemoine',
    subtitle: 'Secrétaire · vous',
    initials: 'SL',
    present: true,
  ),
  _TeamMember(
    name: 'Dr Amélie Rousseau',
    subtitle: 'Praticienne · en consultation',
    initials: 'AR',
    present: true,
  ),
  _TeamMember(
    name: 'Dr Marc Lefèvre',
    subtitle: 'Praticien · absent',
    initials: 'ML',
    present: false,
  ),
  _TeamMember(
    name: 'Claire Béranger',
    subtitle: 'Assistante',
    initials: 'CB',
    present: true,
  ),
];

class _TeamAside extends StatelessWidget {
  const _TeamAside();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      key: const Key('team_aside'),
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: NubiaColors.n200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'Équipe',
                style: textTheme.titleMedium?.copyWith(color: cs.onSurface),
              ),
              const SizedBox(width: 8),
              _TeamCountBadge(count: _teamMembers.length),
            ],
          ),
          const SizedBox(height: 16),
          for (final member in _teamMembers) _TeamMemberRow(member: member),
          const SizedBox(height: 20),
          const _CitedReferencesRecap(),
          const Spacer(),
          const _ClinicalDataReminderNote(),
        ],
      ),
    );
  }
}

class _TeamCountBadge extends StatelessWidget {
  const _TeamCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('team_aside_count_badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: NubiaColors.n100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: NubiaColors.n700,
        ),
      ),
    );
  }
}

class _TeamMemberRow extends StatelessWidget {
  const _TeamMemberRow({required this.member});

  final _TeamMember member;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      key: Key('team_member_${member.initials}'),
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              NubiaAvatar(initials: member.initials, radius: 18),
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  key: Key('team_member_status_${member.initials}'),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: member.present
                        ? NubiaColors.successFg
                        : NubiaColors.n300,
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.surface, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  member.name,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  member.subtitle,
                  style: textTheme.bodySmall?.copyWith(color: NubiaColors.n500),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Récap « Éléments cités aujourd'hui » (#5131) : objets produit référencés
/// dans le fil, en-tête + icône `link` puis une ligne par objet.
class _CitedReferencesRecap extends StatelessWidget {
  const _CitedReferencesRecap();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      key: const Key('team_aside_cited_references'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.link, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Éléments cités aujourd\'hui',
                style: textTheme.labelLarge?.copyWith(color: cs.onSurface),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final cited in _citedReferencesToday)
          _CitedReferenceRow(cited: cited),
      ],
    );
  }
}

class _CitedReferenceRow extends StatelessWidget {
  const _CitedReferenceRow({required this.cited});

  final _CitedReference cited;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: NubiaColors.brand50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(cited.icon, size: 16, color: NubiaColors.brand700),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cited.title,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: NubiaColors.n700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  cited.subtitle,
                  style: textTheme.bodySmall?.copyWith(color: NubiaColors.n500),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<CabinetTeamMessage> _filterMessages(
  List<CabinetTeamMessage> messages,
  String query,
) {
  final trimmed = query.trim().toLowerCase();
  if (trimmed.isEmpty) return messages;
  return messages
      .where((m) =>
          m.body.toLowerCase().contains(trimmed) ||
          m.senderName.toLowerCase().contains(trimmed))
      .toList();
}

String _pad2(int n) => n.toString().padLeft(2, '0');

String _formatTimestamp(DateTime d) =>
    '${_pad2(d.day)}/${_pad2(d.month)} ${_pad2(d.hour)}:${_pad2(d.minute)}';

/// Squelette de chargement du fil : esquisse plusieurs lignes de message
/// (auteur/heure + corps), cohérent avec [_MessagesList].
class _MessagesSkeleton extends StatelessWidget {
  const _MessagesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    NubiaSkeletonLoader(width: 96, height: 12),
                    SizedBox(width: 8),
                    NubiaSkeletonLoader(width: 48, height: 10),
                  ],
                ),
                const SizedBox(height: 6),
                NubiaSkeletonLoader(
                  width: 220 + (i % 3) * 40,
                  height: 14,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MessagesList extends StatelessWidget {
  const _MessagesList({required this.messages, this.isSearching = false});

  final List<CabinetTeamMessage> messages;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return NubiaEmptyState(
        key: const Key('team_messages_empty'),
        icon: isSearching ? Icons.search_off : Icons.forum_outlined,
        title: isSearching ? 'Aucun résultat' : 'Aucun message',
        subtitle: isSearching
            ? 'Essayez un autre terme de recherche.'
            : 'Écrivez le premier message à votre équipe.',
      );
    }
    return ListView.builder(
      key: const Key('team_messages_list'),
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      itemBuilder: (context, i) {
        final m = messages[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            key: Key('team_message_${m.id}'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    m.senderName,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatTimestamp(m.createdAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(m.body),
              if (m.reference != null) _ReferenceChip(reference: m.reference!),
            ],
          ),
        );
      },
    );
  }
}

/// Icône `.ref` associée à un type de référence (#5131, spec design verbatim).
IconData _referenceIcon(CabinetTeamMessageReferenceType type) =>
    switch (type) {
      CabinetTeamMessageReferenceType.patient => Icons.person_outline,
      CabinetTeamMessageReferenceType.devis => Icons.description_outlined,
      CabinetTeamMessageReferenceType.labWorkOrder =>
        Icons.precision_manufacturing,
      CabinetTeamMessageReferenceType.stockRequest => Icons.inventory_2,
      CabinetTeamMessageReferenceType.agendaSlot => Icons.calendar_month,
    };

/// Cible du lien `Ouvrir` d'une référence (#5131) : route existante
/// correspondante quand `app_secretariat` en a une (patient, devis, stock,
/// agenda). Le bon de travail labo n'a pas d'écran dans cette app (seulement
/// dans `app_practicien`) — fallback informatif en attendant.
void _openReference(
  BuildContext context,
  CabinetTeamMessageReference reference,
) {
  switch (reference.type) {
    case CabinetTeamMessageReferenceType.patient:
      context.push('/patients', extra: reference.targetId);
    case CabinetTeamMessageReferenceType.devis:
      context.push('/devis/${reference.targetId}');
    case CabinetTeamMessageReferenceType.stockRequest:
      context.push('/stock');
    case CabinetTeamMessageReferenceType.agendaSlot:
      context.push('/agenda');
    case CabinetTeamMessageReferenceType.labWorkOrder:
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bon de travail labo : écran à venir')),
      );
  }
}

/// Carte référence inline (`.ref`, #5131) : transforme un message en fil de
/// travail en pointant vers l'objet réel du produit qu'il cite.
class _ReferenceChip extends StatelessWidget {
  const _ReferenceChip({required this.reference});

  final CabinetTeamMessageReference reference;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('team_message_reference_${reference.targetId}'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: NubiaColors.n50,
        border: Border.all(color: NubiaColors.n200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(_referenceIcon(reference.type), size: 20, color: NubiaColors.brand700),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reference.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: NubiaColors.n700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  reference.subtitle,
                  style: const TextStyle(fontSize: 12, color: NubiaColors.n500),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            key: Key('team_message_reference_open_${reference.targetId}'),
            onTap: () => _openReference(context, reference),
            child: const Text(
              'Ouvrir',
              style: TextStyle(
                color: NubiaColors.brand700,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  // ⇧⏎ insère un saut de ligne sans envoyer, ⏎ seul envoie (#4538 conservé).
  // Géré manuellement : le clavier physique ne distingue pas les deux dans
  // un champ multiligne sans interception explicite.
  void _insertNewline() {
    final selection = controller.selection;
    final text = controller.text;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    controller.value = TextEditingValue(
      text: text.replaceRange(start, end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    if (!enabled) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isShiftPressed) {
      _insertNewline();
    } else {
      onSend();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              // Scroll horizontal : sur un composeur étroit (mobile), le
              // libellé complet du bouton ne tient pas dans la largeur
              // disponible — NubiaButton ne wrappe pas son label.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: NubiaButton(
                  key: const Key('team_message_attach_reference_button'),
                  label: 'Joindre un patient, un devis…',
                  icon: Icons.link,
                  variant: NubiaButtonVariant.secondary,
                  size: NubiaButtonSize.sm,
                  onPressed: enabled
                      ? () => ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Joindre un objet du produit au message : '
                                'à venir',
                              ),
                            ),
                          )
                      : null,
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Focus(
                    onKeyEvent: _handleKey,
                    child: NubiaTextField(
                      key: const Key('team_message_input'),
                      variant: NubiaTextFieldVariant.multiline,
                      controller: controller,
                      enabled: enabled,
                      hint: 'Écrire à l\'équipe…',
                      onChanged: (_) {},
                      // #4538 : Entrée envoie (réflexe universel dans un chat).
                      onSubmitted: enabled ? (_) => onSend() : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const Key('team_message_send_button'),
                  onPressed: enabled ? onSend : null,
                  icon: const Icon(Icons.send_outlined),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Row(
              key: Key('team_message_keyboard_hints'),
              children: [
                _KeyHint(shortcut: '⏎', label: 'envoyer'),
                SizedBox(width: 8),
                _KeyHint(shortcut: '⇧⏎', label: 'nouvelle ligne'),
              ],
            ),
            const SizedBox(height: 6),
            const _NoClinicalDataHint(),
          ],
        ),
      ),
    );
  }
}

/// Encart note (#5135) : le fil du cabinet est distinct de la messagerie
/// patient, les échanges cliniques restent dans le dossier médical.
class _ClinicalDataReminderNote extends StatelessWidget {
  const _ClinicalDataReminderNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('team_messages_aside_note'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: NubiaColors.n50,
        border: Border.all(color: NubiaColors.n200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield, size: 16, color: NubiaColors.n500),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ce fil est interne au cabinet et distinct de la messagerie '
              'patient. Les échanges cliniques doivent rester dans le '
              'dossier médical.',
              style: TextStyle(fontSize: 11.5, color: NubiaColors.n600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rappel sous le composeur (#5135) : ce fil est interne au cabinet, pas de
/// données cliniques (#4156).
class _NoClinicalDataHint extends StatelessWidget {
  const _NoClinicalDataHint();

  @override
  Widget build(BuildContext context) {
    return const Row(
      key: Key('team_message_no_clinical_data_hint'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.shield, size: 14, color: NubiaColors.n500),
        SizedBox(width: 4),
        // Flexible : sur mobile étroit (400 px, cf. le test #5133 du panneau
        // « Équipe ») le libellé dépasse la largeur du composeur et fait
        // déborder la Row. Flexible le laisse se replier au lieu de rogner.
        Flexible(
          child: Text(
            'Aucune donnée clinique dans ce fil',
            style: TextStyle(fontSize: 11.5, color: NubiaColors.n500),
          ),
        ),
      ],
    );
  }
}

/// Rappel clavier sous le composeur : pastille de raccourci + libellé.
class _KeyHint extends StatelessWidget {
  const _KeyHint({required this.shortcut, required this.label});

  final String shortcut;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: NubiaColors.n50,
            border: Border.all(color: NubiaColors.n200),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            shortcut,
            style: const TextStyle(fontSize: 10, color: NubiaColors.n600),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: NubiaColors.n600),
        ),
      ],
    );
  }
}
