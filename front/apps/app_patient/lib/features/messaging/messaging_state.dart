import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class MessagingState extends Equatable {
  const MessagingState();

  @override
  List<Object?> get props => [];
}

final class MessagingInitial extends MessagingState {
  const MessagingInitial();
}

final class MessagingConversationsLoading extends MessagingState {
  const MessagingConversationsLoading();
}

final class MessagingConversationsLoaded extends MessagingState {
  final List<Conversation> conversations;

  const MessagingConversationsLoaded(this.conversations);

  @override
  List<Object?> get props => [conversations];
}

final class MessagingConversationsError extends MessagingState {
  final String message;

  const MessagingConversationsError(this.message);

  @override
  List<Object?> get props => [message];
}

final class MessagingThreadLoading extends MessagingState {
  final String conversationId;

  const MessagingThreadLoading(this.conversationId);

  @override
  List<Object?> get props => [conversationId];
}

final class MessagingThreadLoaded extends MessagingState {
  final Conversation conversation;
  final List<Message> messages;
  final bool sending;

  const MessagingThreadLoaded({
    required this.conversation,
    required this.messages,
    this.sending = false,
  });

  MessagingThreadLoaded copyWith({
    List<Message>? messages,
    bool? sending,
  }) =>
      MessagingThreadLoaded(
        conversation: conversation,
        messages: messages ?? this.messages,
        sending: sending ?? this.sending,
      );

  @override
  List<Object?> get props => [conversation, messages, sending];
}

final class MessagingThreadError extends MessagingState {
  final String conversationId;
  final String message;

  const MessagingThreadError({
    required this.conversationId,
    required this.message,
  });

  @override
  List<Object?> get props => [conversationId, message];
}
