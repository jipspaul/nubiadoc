import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class PatientMessagesSummaryState extends Equatable {
  const PatientMessagesSummaryState();
}

class PatientMessagesSummaryLoading extends PatientMessagesSummaryState {
  const PatientMessagesSummaryLoading();

  @override
  List<Object?> get props => [];
}

class PatientMessagesSummaryError extends PatientMessagesSummaryState {
  const PatientMessagesSummaryError({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}

class PatientMessagesSummaryLoaded extends PatientMessagesSummaryState {
  const PatientMessagesSummaryLoaded({
    required this.unreadCount,
    required this.urgentUnreadCount,
    this.urgentPatientName,
    this.urgentConversationId,
  });

  final int unreadCount;
  final int urgentUnreadCount;
  final String? urgentPatientName;

  /// Id de la conversation marquée urgente citée par [urgentPatientName] —
  /// permet à l'action « Ouvrir » du tableau de bord (#6246) d'ouvrir cette
  /// conversation précise plutôt que la liste complète.
  final String? urgentConversationId;

  @override
  List<Object?> get props =>
      [unreadCount, urgentUnreadCount, urgentPatientName, urgentConversationId];
}

/// Ligne « messages patients non lus » du panneau « À traiter maintenant »
/// (#5379) : nombre total de messages non lus (`unreadCount` cumulé, même
/// source que le badge du rail, #5388) + mise en avant du(des) message(s)
/// marqué(s) urgent (`triageFlag`, #3556) parmi les conversations non lues.
/// Chargement indépendant du `DashboardBloc`, même découpage que
/// `WaitingRoomSummaryCubit`/`CashCollectionCubit`.
class PatientMessagesSummaryCubit extends Cubit<PatientMessagesSummaryState>
    with SafeEmitMixin<PatientMessagesSummaryState> {
  PatientMessagesSummaryCubit({
    required ListCabinetConversationsUseCase listConversations,
  })  : _listConversations = listConversations,
        super(const PatientMessagesSummaryLoading());

  final ListCabinetConversationsUseCase _listConversations;

  Future<void> load() async {
    safeEmit(const PatientMessagesSummaryLoading());
    final result = await _listConversations();
    result.fold(
      (failure) => safeEmit(PatientMessagesSummaryError(message: failure.message)),
      (conversations) {
        final unreadCount =
            conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);
        final urgentUnread = conversations.where(
          (c) => c.unreadCount > 0 && c.triageFlag == MessageUrgency.urgent,
        );
        safeEmit(
          PatientMessagesSummaryLoaded(
            unreadCount: unreadCount,
            urgentUnreadCount: urgentUnread.length,
            urgentPatientName:
                urgentUnread.isEmpty ? null : urgentUnread.first.patientName,
            urgentConversationId:
                urgentUnread.isEmpty ? null : urgentUnread.first.id,
          ),
        );
      },
    );
  }
}
