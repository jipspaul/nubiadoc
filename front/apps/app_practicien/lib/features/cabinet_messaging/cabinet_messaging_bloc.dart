import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'cabinet_messaging_event.dart';
import 'cabinet_messaging_state.dart';

class CabinetMessagingBloc
    extends Bloc<CabinetMessagingEvent, CabinetMessagingState>
    with SafeEmitMixin<CabinetMessagingState> {
  final ListCabinetConversationsUseCase _listConversations;
  final GetCabinetConversationUseCase _getMessages;
  final SendMessageCabinetUseCase _sendMessage;
  final ConvertConversationToAppointmentUseCase _convertToAppointment;

  CabinetMessagingBloc({
    required ListCabinetConversationsUseCase listConversations,
    required GetCabinetConversationUseCase getMessages,
    required SendMessageCabinetUseCase sendMessage,
    required ConvertConversationToAppointmentUseCase convertToAppointment,
  })  : _listConversations = listConversations,
        _getMessages = getMessages,
        _sendMessage = sendMessage,
        _convertToAppointment = convertToAppointment,
        super(const CabinetMessagingInitial()) {
    on<CabinetMessagingConversationsLoadRequested>(_onConversationsLoad);
    on<CabinetMessagingThreadOpened>(_onThreadOpened);
    on<CabinetMessagingSendRequested>(_onSend);
    on<CabinetMessagingBackRequested>(_onBack);
    on<CabinetMessagingConvertToAppointmentRequested>(_onConvertToAppointment);
  }

  Future<void> _onConversationsLoad(
    CabinetMessagingConversationsLoadRequested event,
    Emitter<CabinetMessagingState> emit,
  ) async {
    emit(const CabinetMessagingConversationsLoading());
    try {
      final result = await _listConversations();
      result.fold(
        (failure) =>
            safeEmit(CabinetMessagingConversationsError(failure.message)),
        (conversations) =>
            safeEmit(CabinetMessagingConversationsLoaded(conversations)),
      );
    } catch (_) {
      safeEmit(
          const CabinetMessagingConversationsError('Erreur de chargement.'));
    }
  }

  Future<void> _onThreadOpened(
    CabinetMessagingThreadOpened event,
    Emitter<CabinetMessagingState> emit,
  ) async {
    emit(CabinetMessagingThreadLoading(event.conversation.id));
    try {
      final result = await _getMessages(event.conversation.id);
      result.fold(
        (failure) => safeEmit(CabinetMessagingThreadError(
          conversationId: event.conversation.id,
          message: failure.message,
        )),
        (messages) => safeEmit(CabinetMessagingThreadLoaded(
          conversation: event.conversation,
          messages: messages,
        )),
      );
    } catch (_) {
      safeEmit(CabinetMessagingThreadError(
          conversationId: event.conversation.id,
          message: 'Erreur de chargement.'));
    }
  }

  Future<void> _onSend(
    CabinetMessagingSendRequested event,
    Emitter<CabinetMessagingState> emit,
  ) async {
    final current = state;
    if (current is! CabinetMessagingThreadLoaded) return;

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
    CabinetMessagingBackRequested event,
    Emitter<CabinetMessagingState> emit,
  ) async {
    emit(const CabinetMessagingConversationsLoading());
    try {
      final result = await _listConversations();
      result.fold(
        (failure) =>
            safeEmit(CabinetMessagingConversationsError(failure.message)),
        (conversations) =>
            safeEmit(CabinetMessagingConversationsLoaded(conversations)),
      );
    } catch (_) {
      safeEmit(
          const CabinetMessagingConversationsError('Erreur de chargement.'));
    }
  }

  Future<void> _onConvertToAppointment(
    CabinetMessagingConvertToAppointmentRequested event,
    Emitter<CabinetMessagingState> emit,
  ) async {
    final current = state;
    if (current is! CabinetMessagingThreadLoaded) return;

    emit(current.copyWith(converting: true, clearConversionError: true));
    try {
      final result = await _convertToAppointment(
        conversationId: event.conversationId,
        slotId: event.slotId,
      );
      result.fold(
        (failure) => safeEmit(current.copyWith(
          converting: false,
          conversionError: failure.message,
        )),
        (_) => safeEmit(
            current.copyWith(converting: false, clearConversionError: true)),
      );
    } catch (_) {
      safeEmit(current.copyWith(
        converting: false,
        conversionError: 'Erreur lors de la conversion en rendez-vous.',
      ));
    }
  }
}
