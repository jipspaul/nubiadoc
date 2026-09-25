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
  final AssignCabinetConversationUseCase _assignConversation;
  final UpdateConversationQualificationUseCase _updateQualification;
  final ListCabinetPractitionersUseCase _listPractitioners;

  CabinetMessagingBloc({
    required ListCabinetConversationsUseCase listConversations,
    required GetCabinetConversationUseCase getMessages,
    required SendMessageCabinetUseCase sendMessage,
    required ConvertConversationToAppointmentUseCase convertToAppointment,
    required AssignCabinetConversationUseCase assignConversation,
    required UpdateConversationQualificationUseCase updateQualification,
    required ListCabinetPractitionersUseCase listPractitioners,
  })  : _listConversations = listConversations,
        _getMessages = getMessages,
        _sendMessage = sendMessage,
        _convertToAppointment = convertToAppointment,
        _assignConversation = assignConversation,
        _updateQualification = updateQualification,
        _listPractitioners = listPractitioners,
        super(const CabinetMessagingInitial()) {
    on<CabinetMessagingConversationsLoadRequested>(_onConversationsLoad);
    on<CabinetMessagingThreadOpened>(_onThreadOpened);
    on<CabinetMessagingSendRequested>(_onSend);
    on<CabinetMessagingBackRequested>(_onBack);
    on<CabinetMessagingConvertToAppointmentRequested>(_onConvertToAppointment);
    on<CabinetMessagingAssigneeChanged>(_onAssigneeChanged);
    on<CabinetMessagingQualificationChanged>(_onQualificationChanged);
  }

  Future<void> _onConversationsLoad(
    CabinetMessagingConversationsLoadRequested event,
    Emitter<CabinetMessagingState> emit,
  ) async {
    emit(const CabinetMessagingConversationsLoading());
    await _loadConversations();
  }

  /// Charge conversations + roster praticiens (#7151/#7150 — colonne
  /// « Praticien » de la vue Secrétariat) en parallèle, même pattern que
  /// `CabinetTeamMessagesCubit.load` : le roster ne bloque jamais l'affichage
  /// des conversations (liste vide en cas d'échec du roster).
  Future<void> _loadConversations() async {
    try {
      final conversationsFuture = _listConversations();
      final practitionersFuture = _listPractitioners();
      final result = await conversationsFuture;
      final practitioners = (await practitionersFuture).fold(
        (_) => const <CabinetPractitioner>[],
        (p) => p,
      );
      result.fold(
        (failure) =>
            safeEmit(CabinetMessagingConversationsError(failure.message)),
        (conversations) => safeEmit(CabinetMessagingConversationsLoaded(
          conversations,
          practitioners: practitioners,
        )),
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
    await _loadConversations();
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

  Future<void> _onAssigneeChanged(
    CabinetMessagingAssigneeChanged event,
    Emitter<CabinetMessagingState> emit,
  ) async {
    final current = state;
    if (current is! CabinetMessagingConversationsLoaded) return;

    try {
      final result = await _assignConversation(
        conversationId: event.conversationId,
        assigneeUserId: event.assigneeUserId,
      );
      result.fold(
        (failure) => safeEmit(current.copyWith(assignError: failure.message)),
        (_) => safeEmit(current.copyWith(
          clearAssignError: true,
          conversations: [
            for (final conv in current.conversations)
              if (conv.id == event.conversationId)
                CabinetConversation(
                  id: conv.id,
                  patientId: conv.patientId,
                  patientName: conv.patientName,
                  patientPhone: conv.patientPhone,
                  unreadCount: conv.unreadCount,
                  lastMessageAt: conv.lastMessageAt,
                  lastMessage: conv.lastMessage,
                  lastMessagePreview: conv.lastMessagePreview,
                  triageFlag: conv.triageFlag,
                  orderRef: conv.orderRef,
                  orderStatusLabel: conv.orderStatusLabel,
                  status: conv.status,
                  priority: conv.priority,
                  origin: conv.origin,
                  summary: conv.summary,
                  assigneeUserId: event.assigneeUserId,
                )
              else
                conv,
          ],
        )),
      );
    } catch (_) {
      safeEmit(
        current.copyWith(assignError: 'Erreur lors de l\'assignation.'),
      );
    }
  }

  /// Qualifie la conversation ouverte (#7609) — met à jour l'entrée locale
  /// pour un rendu immédiat de l'éditeur ; la liste se resynchronise au
  /// retour (`_onBack` recharge toujours depuis l'API).
  Future<void> _onQualificationChanged(
    CabinetMessagingQualificationChanged event,
    Emitter<CabinetMessagingState> emit,
  ) async {
    final current = state;
    if (current is! CabinetMessagingThreadLoaded) return;

    emit(current.copyWith(qualifying: true, clearQualificationError: true));
    try {
      final result = await _updateQualification(
        conversationId: event.conversationId,
        origin: event.origin,
        priority: event.priority,
        status: event.status,
        summary: event.summary,
      );
      result.fold(
        (failure) => safeEmit(current.copyWith(
          qualifying: false,
          qualificationError: failure.message,
        )),
        (_) => safeEmit(current.copyWith(
          qualifying: false,
          clearQualificationError: true,
          conversation: CabinetConversation(
            id: current.conversation.id,
            patientId: current.conversation.patientId,
            patientName: current.conversation.patientName,
            patientPhone: current.conversation.patientPhone,
            unreadCount: current.conversation.unreadCount,
            lastMessageAt: current.conversation.lastMessageAt,
            lastMessage: current.conversation.lastMessage,
            lastMessagePreview: current.conversation.lastMessagePreview,
            triageFlag: current.conversation.triageFlag,
            orderRef: current.conversation.orderRef,
            orderStatusLabel: current.conversation.orderStatusLabel,
            status: event.status ?? current.conversation.status,
            priority: event.priority ?? current.conversation.priority,
            origin: event.origin ?? current.conversation.origin,
            summary: event.summary ?? current.conversation.summary,
            assigneeUserId: current.conversation.assigneeUserId,
          ),
        )),
      );
    } catch (_) {
      safeEmit(current.copyWith(
        qualifying: false,
        qualificationError: 'Erreur lors de la qualification.',
      ));
    }
  }
}
