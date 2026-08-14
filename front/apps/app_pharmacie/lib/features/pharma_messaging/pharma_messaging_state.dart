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
  // Liste conservée pendant le chargement du fil pour le layout deux
  // volets (#4925) : la colonne liste reste affichée sur poste comptoir.
  final List<CabinetConversation> conversations;

  const PharmaMessagingThreadLoading(
    this.conversationId, {
    this.conversations = const [],
  });

  @override
  List<Object?> get props => [conversationId, conversations];
}

final class PharmaMessagingThreadLoaded extends PharmaMessagingState {
  final CabinetConversation conversation;
  final List<Message> messages;
  final bool sending;
  final List<CabinetConversation> conversations;

  const PharmaMessagingThreadLoaded({
    required this.conversation,
    required this.messages,
    this.sending = false,
    this.conversations = const [],
  });

  PharmaMessagingThreadLoaded copyWith({
    List<Message>? messages,
    bool? sending,
    List<CabinetConversation>? conversations,
  }) =>
      PharmaMessagingThreadLoaded(
        conversation: conversation,
        messages: messages ?? this.messages,
        sending: sending ?? this.sending,
        conversations: conversations ?? this.conversations,
      );

  @override
  List<Object?> get props => [conversation, messages, sending, conversations];
}

final class PharmaMessagingThreadError extends PharmaMessagingState {
  final String conversationId;
  final String message;
  final List<CabinetConversation> conversations;

  const PharmaMessagingThreadError({
    required this.conversationId,
    required this.message,
    this.conversations = const [],
  });

  @override
  List<Object?> get props => [conversationId, message, conversations];
}
