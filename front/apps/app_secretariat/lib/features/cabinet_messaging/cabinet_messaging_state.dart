import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class CabinetMessagingState extends Equatable {
  const CabinetMessagingState();

  @override
  List<Object?> get props => [];
}

final class CabinetMessagingInitial extends CabinetMessagingState {
  const CabinetMessagingInitial();
}

final class CabinetMessagingConversationsLoading extends CabinetMessagingState {
  const CabinetMessagingConversationsLoading();
}

final class CabinetMessagingConversationsLoaded extends CabinetMessagingState {
  final List<CabinetConversation> conversations;

  const CabinetMessagingConversationsLoaded(this.conversations);

  @override
  List<Object?> get props => [conversations];
}

final class CabinetMessagingConversationsError extends CabinetMessagingState {
  final String message;

  const CabinetMessagingConversationsError(this.message);

  @override
  List<Object?> get props => [message];
}

final class CabinetMessagingThreadLoading extends CabinetMessagingState {
  final String conversationId;

  const CabinetMessagingThreadLoading(this.conversationId);

  @override
  List<Object?> get props => [conversationId];
}

final class CabinetMessagingThreadLoaded extends CabinetMessagingState {
  final CabinetConversation conversation;
  final List<Message> messages;
  final bool sending;

  /// Conversion en RDV en cours (#4159/#4160) — désactive le bouton "Créer un
  /// RDV" pendant l'appel.
  final bool converting;

  /// Message d'erreur de la dernière tentative de conversion, `null` sinon.
  final String? conversionError;

  const CabinetMessagingThreadLoaded({
    required this.conversation,
    required this.messages,
    this.sending = false,
    this.converting = false,
    this.conversionError,
  });

  CabinetMessagingThreadLoaded copyWith({
    List<Message>? messages,
    bool? sending,
    bool? converting,
    String? conversionError,
    bool clearConversionError = false,
  }) =>
      CabinetMessagingThreadLoaded(
        conversation: conversation,
        messages: messages ?? this.messages,
        sending: sending ?? this.sending,
        converting: converting ?? this.converting,
        conversionError: clearConversionError
            ? null
            : (conversionError ?? this.conversionError),
      );

  @override
  List<Object?> get props =>
      [conversation, messages, sending, converting, conversionError];
}

final class CabinetMessagingThreadError extends CabinetMessagingState {
  final String conversationId;
  final String message;

  const CabinetMessagingThreadError({
    required this.conversationId,
    required this.message,
  });

  @override
  List<Object?> get props => [conversationId, message];
}
