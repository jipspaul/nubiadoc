import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_bloc.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_event.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_state.dart';
import 'package:nubia_patient/presentation/features/messaging/widgets/message_bubble.dart';
import 'package:nubia_patient/presentation/features/messaging/widgets/message_input_bar.dart';

/// Full message thread for a single [conversationId].
///
/// Expects [MessagingBloc] to be provided by the parent (typically [AppRouter]).
class MessageThreadScreen extends StatelessWidget {
  const MessageThreadScreen({
    super.key,
    required this.conversationId,
    required this.cabinetName,
  });

  final String conversationId;
  final String cabinetName;

  @override
  Widget build(BuildContext context) {
    return BlocListener<MessagingBloc, MessagingState>(
      listener: (context, state) {
        if (state is MessagingThreadError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(cabinetName)),
        body: Column(
          children: [
            Expanded(
              child: BlocBuilder<MessagingBloc, MessagingState>(
                builder: (context, state) {
                  if (state is MessagingThreadLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (state is MessagingThreadLoaded) {
                    if (state.messages.isEmpty) {
                      return const _EmptyThread();
                    }
                    return _MessageList(
                      conversationId: conversationId,
                      state: state,
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            BlocBuilder<MessagingBloc, MessagingState>(
              builder: (context, state) {
                final sending =
                    state is MessagingThreadLoaded && state.sending;
                return MessageInputBar(
                  enabled: !sending,
                  onSend: (text) {
                    context.read<MessagingBloc>().add(
                          MessagingMessageSendRequested(
                            conversationId: conversationId,
                            text: text,
                          ),
                        );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.conversationId,
    required this.state,
  });

  final String conversationId;
  final MessagingThreadLoaded state;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.messages.length,
      itemBuilder: (context, index) {
        // reverse list so newest is at bottom
        final message =
            state.messages[state.messages.length - 1 - index];
        return MessageBubble(message: message);
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _EmptyThread extends StatelessWidget {
  const _EmptyThread();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Aucun message. Commencez la conversation.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
