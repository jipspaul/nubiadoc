import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class PharmaMessagingState extends Equatable {
  const PharmaMessagingState();

  @override
  List<Object?> get props => [];
}

final class PharmaMessagingInitial extends PharmaMessagingState {
  const PharmaMessagingInitial();
}

final class PharmaMessagingConversationsLoading extends PharmaMessagingState {
  const PharmaMessagingConversationsLoading();
}

final class PharmaMessagingConversationsLoaded extends PharmaMessagingState {
  final List<CabinetConversation> conversations;

  const PharmaMessagingConversationsLoaded(this.conversations);

  @override
  List<Object?> get props => [conversations];
}

final class PharmaMessagingConversationsError extends PharmaMessagingState {
  final String message;

  const PharmaMessagingConversationsError(this.message);

  @override
  List<Object?> get props => [message];
}

final class PharmaMessagingThreadLoading extends PharmaMessagingState {
  final String conversationId;

  const PharmaMessagingThreadLoading(this.conversationId);

  @override
  List<Object?> get props => [conversationId];
}

final class PharmaMessagingThreadLoaded extends PharmaMessagingState {
  final CabinetConversation conversation;
  final List<Message> messages;
  final bool sending;

  const PharmaMessagingThreadLoaded({
    required this.conversation,
    required this.messages,
    this.sending = false,
  });

  PharmaMessagingThreadLoaded copyWith({
    List<Message>? messages,
    bool? sending,
  }) =>
      PharmaMessagingThreadLoaded(
        conversation: conversation,
        messages: messages ?? this.messages,
        sending: sending ?? this.sending,
      );

  @override
  List<Object?> get props => [conversation, messages, sending];
}

final class PharmaMessagingThreadError extends PharmaMessagingState {
  final String conversationId;
  final String message;

  const PharmaMessagingThreadError({
    required this.conversationId,
    required this.message,
  });

  @override
  List<Object?> get props => [conversationId, message];
}
