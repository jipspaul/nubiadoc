//! Écran de messagerie interne d'équipe (#4156) — fil unique du cabinet,
//! staff↔staff, distinct de la messagerie patient (cabinet_messaging).

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
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
      child: const Scaffold(
        appBar: _TeamMessagesAppBar(),
        body: _TeamMessagesBody(),
      ),
    );
  }
}

class _TeamMessagesAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _TeamMessagesAppBar();

  @override
  Widget build(BuildContext context) =>
      AppBar(title: const Text('Messagerie interne'));

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _TeamMessagesBody extends StatefulWidget {
  const _TeamMessagesBody();

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
        return Column(
          children: [
            Expanded(
              child: switch (state) {
                CabinetTeamMessagesLoading() => const Center(
                    key: Key('team_messages_loading'),
                    child: CircularProgressIndicator(),
                  ),
                CabinetTeamMessagesError(:final message) => NubiaErrorWidget(
                    key: const Key('team_messages_error'),
                    message: message,
                    onRetry: () =>
                        context.read<CabinetTeamMessagesCubit>().load(),
                  ),
                CabinetTeamMessagesLoaded(:final messages) =>
                  _MessagesList(messages: messages),
              },
            ),
            _Composer(
              controller: _controller,
              enabled: state is CabinetTeamMessagesLoaded && !state.sending,
              onSend: () => _send(context),
            ),
          ],
        );
      },
    );
  }
}

String _pad2(int n) => n.toString().padLeft(2, '0');

String _formatTimestamp(DateTime d) =>
    '${_pad2(d.day)}/${_pad2(d.month)} ${_pad2(d.hour)}:${_pad2(d.minute)}';

class _MessagesList extends StatelessWidget {
  const _MessagesList({required this.messages});

  final List<CabinetTeamMessage> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const NubiaEmptyState(
        key: Key('team_messages_empty'),
        icon: Icons.forum_outlined,
        title: 'Aucun message',
        subtitle: 'Écrivez le premier message à votre équipe.',
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
            ],
          ),
        );
      },
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: NubiaTextField(
                key: const Key('team_message_input'),
                variant: NubiaTextFieldVariant.outlined,
                controller: controller,
                enabled: enabled,
                hint: 'Écrire un message à l\'équipe…',
                onChanged: (_) {},
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const Key('team_message_send_button'),
              tooltip: 'Envoyer',
              onPressed: enabled ? onSend : null,
              icon: const Icon(Icons.send_outlined),
            ),
          ],
        ),
      ),
    );
  }
}
