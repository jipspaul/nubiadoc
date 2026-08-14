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

  /// Commandes passées du patient de cette conversation, pour la colonne
  /// contexte (#4926) — meilleur effort côté client (filtrage par nom
  /// affiché, cf. `PharmaMessagingBloc._patientOrdersOf`).
  final List<PharmacyOrder> patientOrders;

  const PharmaMessagingThreadLoaded({
    required this.conversation,
    required this.messages,
    this.sending = false,
    this.conversations = const [],
    this.patientOrders = const [],
  });

  PharmaMessagingThreadLoaded copyWith({
    List<Message>? messages,
    bool? sending,
    List<CabinetConversation>? conversations,
    List<PharmacyOrder>? patientOrders,
  }) =>
      PharmaMessagingThreadLoaded(
        conversation: conversation,
        messages: messages ?? this.messages,
        sending: sending ?? this.sending,
        conversations: conversations ?? this.conversations,
        patientOrders: patientOrders ?? this.patientOrders,
      );

  @override
  List<Object?> get props =>
      [conversation, messages, sending, conversations, patientOrders];
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
