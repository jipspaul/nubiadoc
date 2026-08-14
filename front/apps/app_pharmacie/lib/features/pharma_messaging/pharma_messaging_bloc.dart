import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'pharma_messaging_event.dart';
import 'pharma_messaging_state.dart';

class PharmaMessagingBloc
    extends Bloc<PharmaMessagingEvent, PharmaMessagingState>
    with SafeEmitMixin<PharmaMessagingState> {
  final ListCabinetConversationsUseCase _listConversations;
  final GetCabinetConversationUseCase _getMessages;
  final SendMessageCabinetUseCase _sendMessage;
  final ListPharmacyOrdersUseCase _listOrders;

  PharmaMessagingBloc({
    required ListCabinetConversationsUseCase listConversations,
    required GetCabinetConversationUseCase getMessages,
    required SendMessageCabinetUseCase sendMessage,
    required ListPharmacyOrdersUseCase listOrders,
  })  : _listConversations = listConversations,
        _getMessages = getMessages,
        _sendMessage = sendMessage,
        _listOrders = listOrders,
        super(const PharmaMessagingInitial()) {
    on<PharmaMessagingConversationsLoadRequested>(_onConversationsLoad);
    on<PharmaMessagingThreadOpened>(_onThreadOpened);
    on<PharmaMessagingSendRequested>(_onSend);
    on<PharmaMessagingBackRequested>(_onBack);
  }

  Future<void> _onConversationsLoad(
    PharmaMessagingConversationsLoadRequested event,
    Emitter<PharmaMessagingState> emit,
  ) async {
    emit(const PharmaMessagingConversationsLoading());
    try {
      final result = await _listConversations();
      result.fold(
        (failure) =>
            safeEmit(PharmaMessagingConversationsError(failure.message)),
        (conversations) =>
            safeEmit(PharmaMessagingConversationsLoaded(conversations)),
      );
    } catch (_) {
      safeEmit(
          const PharmaMessagingConversationsError('Erreur de chargement.'));
    }
  }

  Future<void> _onThreadOpened(
    PharmaMessagingThreadOpened event,
    Emitter<PharmaMessagingState> emit,
  ) async {
    final conversations = _conversationsOf(state);
    emit(PharmaMessagingThreadLoading(
      event.conversation.id,
      conversations: conversations,
    ));
    try {
      final result = await _getMessages(event.conversation.id);
      await result.fold(
        (failure) async => safeEmit(PharmaMessagingThreadError(
          conversationId: event.conversation.id,
          message: failure.message,
          conversations: conversations,
        )),
        (messages) async => safeEmit(PharmaMessagingThreadLoaded(
          conversation: event.conversation,
          messages: messages,
          conversations: conversations,
          patientOrders: await _patientOrdersOf(event.conversation),
        )),
      );
    } catch (_) {
      safeEmit(PharmaMessagingThreadError(
        conversationId: event.conversation.id,
        message: 'Erreur de chargement.',
        conversations: conversations,
      ));
    }
  }

  /// Conversations connues par l'état courant, quel qu'il soit — permet de
  /// garder la colonne liste affichée pendant l'ouverture d'un fil (#4925).
  List<CabinetConversation> _conversationsOf(PharmaMessagingState state) =>
      switch (state) {
        PharmaMessagingConversationsLoaded(:final conversations) =>
          conversations,
        PharmaMessagingThreadLoading(:final conversations) => conversations,
        PharmaMessagingThreadLoaded(:final conversations) => conversations,
        PharmaMessagingThreadError(:final conversations) => conversations,
        _ => const [],
      };

  /// Historique des commandes du patient pour la colonne contexte (#4926).
  /// `GET /v1/pharmacy/orders` n'est pas filtrable par patient (pas de
  /// `patient_id` dans le contrat, seulement `patient_display_name`) —
  /// on récupère les commandes de l'officine et on filtre côté client par
  /// nom affiché. Un échec ici ne doit pas empêcher l'ouverture du fil : la
  /// colonne contexte s'affiche simplement sans section commandes.
  Future<List<PharmacyOrder>> _patientOrdersOf(
    CabinetConversation conversation,
  ) async {
    try {
      final result = await _listOrders();
      return result.fold(
        (_) => const [],
        (orders) => orders
            .where((o) =>
                o.patientDisplayName?.trim().toLowerCase() ==
                conversation.patientName.trim().toLowerCase())
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );
    } catch (_) {
      return const [];
    }
  }

  Future<void> _onSend(
    PharmaMessagingSendRequested event,
    Emitter<PharmaMessagingState> emit,
  ) async {
    final current = state;
    if (current is! PharmaMessagingThreadLoaded) return;

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
    PharmaMessagingBackRequested event,
    Emitter<PharmaMessagingState> emit,
  ) async {
    emit(const PharmaMessagingConversationsLoading());
    try {
      final result = await _listConversations();
      result.fold(
        (failure) =>
            safeEmit(PharmaMessagingConversationsError(failure.message)),
        (conversations) =>
            safeEmit(PharmaMessagingConversationsLoaded(conversations)),
      );
    } catch (_) {
      safeEmit(
          const PharmaMessagingConversationsError('Erreur de chargement.'));
    }
  }
}
