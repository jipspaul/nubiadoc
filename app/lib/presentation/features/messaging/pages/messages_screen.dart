import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_patient/core/di/injection.dart';
import 'package:nubia_patient/core/router/route_names.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_bloc.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_event.dart';
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_state.dart';
import 'package:nubia_patient/presentation/features/messaging/widgets/conversation_tile.dart';

/// Lists all conversations for the patient.
///
/// Provides [MessagingBloc] via [BlocProvider] scoped to this screen.
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<MessagingBloc>()
        ..add(const MessagingConversationsLoadRequested()),
      child: const _MessagesBody(),
    );
  }
}

// ---------------------------------------------------------------------------

class _MessagesBody extends StatelessWidget {
  const _MessagesBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: BlocBuilder<MessagingBloc, MessagingState>(
        builder: (context, state) {
          if (state is MessagingConversationsLoading ||
              state is MessagingInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is MessagingConversationsError) {
            return Center(child: Text(state.message));
          }
          if (state is MessagingConversationsLoaded) {
            if (state.conversations.isEmpty) {
              return const _EmptyConversations();
            }
            return ListView.separated(
              itemCount: state.conversations.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final conversation = state.conversations[index];
                return ConversationTile(
                  conversation: conversation,
                  onTap: () => context.push(
                    RouteNames.messageThread.replaceFirst(
                      ':id',
                      conversation.id,
                    ),
                    extra: conversation.cabinetName,
                  ),
                );
              },
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _EmptyConversations extends StatelessWidget {
  const _EmptyConversations();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
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
      ),
    );
  }
}
