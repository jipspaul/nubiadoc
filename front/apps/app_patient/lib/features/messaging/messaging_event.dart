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

/// Ouverture d'un fil dont on ne connaît que l'identifiant (#6399) : route
/// `:id` atteinte par URL directe (deep link / rechargement de page), sans
/// le `Conversation` que le chemin liste -> clic fournit via `extra`.
final class MessagingThreadRequested extends MessagingEvent {
  final String conversationId;

  const MessagingThreadRequested(this.conversationId);

  @override
  List<Object?> get props => [conversationId];
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
