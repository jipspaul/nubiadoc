import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'messaging_event.dart';
import 'messaging_state.dart';

class MessagingBloc extends Bloc<MessagingEvent, MessagingState>
    with SafeEmitMixin<MessagingState> {
  final GetConversationsUseCase _getConversations;
  final GetConversationMessagesUseCase _getMessages;
  final SendMessageUseCase _sendMessage;
  final MarkConversationReadUseCase _markRead;

  /// Conversations ouvertes localement pendant la session courante.
  ///
  /// Règle retenue (#5286) : un fil est marqué lu à son *ouverture*, pas à
  /// l'affichage effectif de chaque message — un appel explicite par message
  /// visible demanderait un événement que l'UI n'émet pas aujourd'hui. En
  /// contrepartie, la pastille ne doit pas dépendre du seul rechargement
  /// serveur : on retient ici les fils lus localement pour forcer leur
  /// `unreadCount` à 0 dans tout état `MessagingConversationsLoaded` émis
  /// ensuite, y compris si l'appel `_markRead` échoue silencieusement ou si
  /// le serveur n'a pas encore propagé la lecture.
  final Set<String> _locallyReadConversationIds = {};

  MessagingBloc({
    required GetConversationsUseCase getConversations,
    required GetConversationMessagesUseCase getMessages,
    required SendMessageUseCase sendMessage,
    required MarkConversationReadUseCase markRead,
  })  : _getConversations = getConversations,
        _getMessages = getMessages,
        _sendMessage = sendMessage,
        _markRead = markRead,
        super(const MessagingInitial()) {
    on<MessagingConversationsLoadRequested>(_onConversationsLoad);
    on<MessagingThreadOpened>(_onThreadOpened);
    on<MessagingThreadRequested>(_onThreadRequested);
    on<MessagingSendRequested>(_onSend);
    on<MessagingBackRequested>(_onBack);
  }

  Future<void> _onConversationsLoad(
    MessagingConversationsLoadRequested event,
    Emitter<MessagingState> emit,
  ) async {
    emit(const MessagingConversationsLoading());
    try {
      final result = await _getConversations();
      result.fold(
        (failure) => safeEmit(MessagingConversationsError(failure.message)),
        (conversations) => safeEmit(
            MessagingConversationsLoaded(_withLocalReadState(conversations))),
      );
    } catch (_) {
      safeEmit(const MessagingConversationsError('Erreur de chargement.'));
    }
  }

  Future<void> _onThreadOpened(
    MessagingThreadOpened event,
    Emitter<MessagingState> emit,
  ) =>
      _loadThread(event.conversation, emit);

  /// Deep link / rechargement de page (#6399) : seul l'identifiant est
  /// connu (`pathParameters['id']`), il n'y a pas de [Conversation] fournie
  /// en `extra` par une liste déjà chargée. On la retrouve via l'API avant
  /// d'ouvrir le fil, pour éviter de déréférencer un objet absent.
  Future<void> _onThreadRequested(
    MessagingThreadRequested event,
    Emitter<MessagingState> emit,
  ) async {
    emit(MessagingThreadLoading(event.conversationId));
    final result = await _getConversations();
    final conversation = result.fold<Conversation?>(
      (_) => null,
      (conversations) {
        for (final candidate in conversations) {
          if (candidate.id == event.conversationId) return candidate;
        }
        return null;
      },
    );
    if (conversation == null) {
      safeEmit(MessagingThreadError(
        conversationId: event.conversationId,
        message: 'Conversation introuvable.',
      ));
      return;
    }
    await _loadThread(conversation, emit);
  }

  Future<void> _loadThread(
    Conversation conversation,
    Emitter<MessagingState> emit,
  ) async {
    emit(MessagingThreadLoading(conversation.id));
    try {
      final result = await _getMessages(conversation.id);
      result.fold(
        (failure) => safeEmit(MessagingThreadError(
          conversationId: conversation.id,
          message: failure.message,
        )),
        (messages) => safeEmit(MessagingThreadLoaded(
          conversation: conversation,
          messages: messages,
        )),
      );
    } catch (_) {
      safeEmit(MessagingThreadError(
          conversationId: conversation.id,
          message: 'Erreur de chargement.'));
    }
    // Marqué lu localement dès l'ouverture, indépendamment du résultat de
    // l'appel serveur ci-dessus : la pastille ne doit pas se rallumer si
    // `_markRead` échoue (best effort, fire-and-forget).
    _locallyReadConversationIds.add(conversation.id);
    await _markRead(conversation.id);
  }

  Future<void> _onSend(
    MessagingSendRequested event,
    Emitter<MessagingState> emit,
  ) async {
    final current = state;
    if (current is! MessagingThreadLoaded) return;

    emit(current.copyWith(sending: true));
    try {
      final result = await _sendMessage(
        conversationId: event.conversationId,
        text: event.text,
      );
      result.fold(
        (failure) => safeEmit(current.copyWith(sending: false)),
        (message) => safeEmit(current.copyWith(
          sending: false,
          messages: [...current.messages, message],
        )),
      );
    } catch (_) {
      safeEmit(current.copyWith(sending: false));
    }
  }

  Future<void> _onBack(
    MessagingBackRequested event,
    Emitter<MessagingState> emit,
  ) async {
    emit(const MessagingConversationsLoading());
    try {
      final result = await _getConversations();
      result.fold(
        (failure) => safeEmit(MessagingConversationsError(failure.message)),
        (conversations) => safeEmit(
            MessagingConversationsLoaded(_withLocalReadState(conversations))),
      );
    } catch (_) {
      safeEmit(const MessagingConversationsError('Erreur de chargement.'));
    }
  }

  /// Force à 0 le `unreadCount` des conversations lues localement pendant
  /// la session (voir [_locallyReadConversationIds]), même si le serveur
  /// n'a pas encore propagé la lecture.
  List<Conversation> _withLocalReadState(List<Conversation> conversations) {
    if (_locallyReadConversationIds.isEmpty) return conversations;
    return [
      for (final conversation in conversations)
        if (_locallyReadConversationIds.contains(conversation.id))
          conversation.copyWith(unreadCount: 0)
        else
          conversation,
    ];
  }
}
