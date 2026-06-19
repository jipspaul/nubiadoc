import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class MessagingEvent extends Equatable {
  const MessagingEvent();

  @override
  List<Object?> get props => [];
}

final class MessagingConversationsLoadRequested extends MessagingEvent {
  const MessagingConversationsLoadRequested();
}

final class MessagingThreadOpened extends MessagingEvent {
  final Conversation conversation;

  const MessagingThreadOpened(this.conversation);

  @override
  List<Object?> get props => [conversation];
}

final class MessagingSendRequested extends MessagingEvent {
  final String conversationId;
  final String text;

  const MessagingSendRequested({
    required this.conversationId,
    required this.text,
  });

  @override
  List<Object?> get props => [conversationId, text];
}

final class MessagingBackRequested extends MessagingEvent {
  const MessagingBackRequested();
}
