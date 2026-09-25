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

  /// Roster réel du cabinet (#7151/#7150 — colonne « Praticien » de la vue
  /// Secrétariat), même source que l'agenda secrétariat
  /// (`ListCabinetPractitionersUseCase`) — sert à résoudre `assigneeUserId`
  /// en nom affichable et à peupler le sélecteur d'assignation.
  final List<CabinetPractitioner> practitioners;

  /// Message d'erreur de la dernière tentative d'assignation (#7151/#7150),
  /// `null` sinon — même sémantique que `conversionError` du fil.
  final String? assignError;

  const CabinetMessagingConversationsLoaded(
    this.conversations, {
    this.practitioners = const [],
    this.assignError,
  });

  CabinetMessagingConversationsLoaded copyWith({
    List<CabinetConversation>? conversations,
    List<CabinetPractitioner>? practitioners,
    String? assignError,
    bool clearAssignError = false,
  }) =>
      CabinetMessagingConversationsLoaded(
        conversations ?? this.conversations,
        practitioners: practitioners ?? this.practitioners,
        assignError:
            clearAssignError ? null : (assignError ?? this.assignError),
      );

  @override
  List<Object?> get props => [conversations, practitioners, assignError];
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

  /// Qualification (origine/priorité/statut/synthèse) en cours d'envoi
  /// (#7609) — désactive le bouton de sauvegarde de l'éditeur pendant l'appel.
  final bool qualifying;

  /// Message d'erreur de la dernière tentative de qualification, `null`
  /// sinon — même sémantique que [conversionError].
  final String? qualificationError;

  const CabinetMessagingThreadLoaded({
    required this.conversation,
    required this.messages,
    this.sending = false,
    this.converting = false,
    this.conversionError,
    this.qualifying = false,
    this.qualificationError,
  });

  CabinetMessagingThreadLoaded copyWith({
    CabinetConversation? conversation,
    List<Message>? messages,
    bool? sending,
    bool? converting,
    String? conversionError,
    bool clearConversionError = false,
    bool? qualifying,
    String? qualificationError,
    bool clearQualificationError = false,
  }) =>
      CabinetMessagingThreadLoaded(
        conversation: conversation ?? this.conversation,
        messages: messages ?? this.messages,
        sending: sending ?? this.sending,
        converting: converting ?? this.converting,
        conversionError: clearConversionError
            ? null
            : (conversionError ?? this.conversionError),
        qualifying: qualifying ?? this.qualifying,
        qualificationError: clearQualificationError
            ? null
            : (qualificationError ?? this.qualificationError),
      );

  @override
  List<Object?> get props => [
        conversation,
        messages,
        sending,
        converting,
        conversionError,
        qualifying,
        qualificationError,
      ];
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
