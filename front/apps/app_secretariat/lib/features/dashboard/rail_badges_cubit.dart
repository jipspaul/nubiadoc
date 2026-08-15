import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Fenêtre d'échéance retenue pour un devis « expirant » (#5388) : envoyé au
/// patient, pas encore signé, avec une date d'expiration dans les 7 prochains
/// jours — la maquette ne précise pas de seuil, celui-ci aligne le badge sur
/// une urgence à traiter dans la semaine plutôt que tout devis à échéance.
const _expiringQuoteWindow = Duration(days: 7);

/// Compteurs des badges du rail secrétariat (#5388) : Salle d'attente,
/// Demandes de créneau, Devis expirants, Messages non lus.
class RailBadgesState extends Equatable {
  const RailBadgesState({
    this.waitingRoomCount = 0,
    this.waitingListCount = 0,
    this.expiringQuotesCount = 0,
    this.unreadMessagesCount = 0,
  });

  final int waitingRoomCount;
  final int waitingListCount;
  final int expiringQuotesCount;
  final int unreadMessagesCount;

  @override
  List<Object?> get props => [
        waitingRoomCount,
        waitingListCount,
        expiringQuotesCount,
        unreadMessagesCount,
      ];
}

/// Alimente les badges du rail avec les mêmes sources que les lignes de la
/// file « À traiter maintenant » (#5388) : salle d'attente, liste d'attente
/// (demandes de créneau), devis expirants, messages patients non lus. Chaque
/// compteur est best-effort — l'échec d'une source retombe à 0 plutôt que de
/// bloquer l'ouverture du tableau de bord (même logique que `DashboardBloc`
/// pour la liste d'attente, #3362).
class RailBadgesCubit extends Cubit<RailBadgesState>
    with SafeEmitMixin<RailBadgesState> {
  RailBadgesCubit({
    required ListWaitingRoomUseCase listWaitingRoom,
    required ListWaitingListUseCase listWaitingList,
    required ListCabinetQuotesUseCase listQuotes,
    required ListCabinetConversationsUseCase listConversations,
  })  : _listWaitingRoom = listWaitingRoom,
        _listWaitingList = listWaitingList,
        _listQuotes = listQuotes,
        _listConversations = listConversations,
        super(const RailBadgesState());

  final ListWaitingRoomUseCase _listWaitingRoom;
  final ListWaitingListUseCase _listWaitingList;
  final ListCabinetQuotesUseCase _listQuotes;
  final ListCabinetConversationsUseCase _listConversations;

  Future<void> load() async {
    final now = DateTime.now();

    Future<int> waitingRoomCount() async {
      final result = await _listWaitingRoom();
      return result.fold((_) => 0, (entries) => entries.length);
    }

    Future<int> waitingListCount() async {
      final result = await _listWaitingList();
      return result.fold((_) => 0, (entries) => entries.length);
    }

    Future<int> expiringQuotesCount() async {
      final result = await _listQuotes();
      return result.fold(
        (_) => 0,
        (quotes) => quotes
            .where(
              (q) =>
                  q.status == CabinetQuoteStatus.sent &&
                  q.expiresAt != null &&
                  q.expiresAt!.isAfter(now) &&
                  q.expiresAt!.isBefore(now.add(_expiringQuoteWindow)),
            )
            .length,
      );
    }

    Future<int> unreadMessagesCount() async {
      final result = await _listConversations();
      return result.fold(
        (_) => 0,
        (conversations) =>
            conversations.fold<int>(0, (sum, c) => sum + c.unreadCount),
      );
    }

    try {
      final counts = await Future.wait([
        waitingRoomCount(),
        waitingListCount(),
        expiringQuotesCount(),
        unreadMessagesCount(),
      ]);
      safeEmit(
        RailBadgesState(
          waitingRoomCount: counts[0],
          waitingListCount: counts[1],
          expiringQuotesCount: counts[2],
          unreadMessagesCount: counts[3],
        ),
      );
    } catch (_) {
      // Best-effort : les badges sont secondaires, une erreur inattendue les
      // laisse à 0 (état initial) plutôt que de casser le tableau de bord.
    }
  }
}
