import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class WaitingRoomSummaryState extends Equatable {
  const WaitingRoomSummaryState();
}

class WaitingRoomSummaryLoading extends WaitingRoomSummaryState {
  const WaitingRoomSummaryLoading();

  @override
  List<Object?> get props => [];
}

class WaitingRoomSummaryError extends WaitingRoomSummaryState {
  const WaitingRoomSummaryError({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}

class WaitingRoomSummaryLoaded extends WaitingRoomSummaryState {
  const WaitingRoomSummaryLoaded({
    required this.presentCount,
    required this.averageWaitMinutes,
    required this.longestWaitMinutes,
  });

  final int presentCount;
  final int averageWaitMinutes;
  final int longestWaitMinutes;

  @override
  List<Object?> get props =>
      [presentCount, averageWaitMinutes, longestWaitMinutes];
}

/// Carte « Salle d'attente » du tableau de bord (#5381) : effectif présent +
/// attente moyenne/la plus longue, dérivés de la même source que
/// `WaitingRoomBloc` (`ListWaitingRoomUseCase`). Chargement indépendant du
/// `DashboardBloc` — même découpage que `CashCollectionCubit`/
/// `RailBadgesCubit`, cette donnée n'a pas de source commune avec l'agenda.
class WaitingRoomSummaryCubit extends Cubit<WaitingRoomSummaryState>
    with SafeEmitMixin<WaitingRoomSummaryState> {
  WaitingRoomSummaryCubit({required ListWaitingRoomUseCase listWaitingRoom})
      : _listWaitingRoom = listWaitingRoom,
        super(const WaitingRoomSummaryLoading());

  final ListWaitingRoomUseCase _listWaitingRoom;

  Future<void> load() async {
    safeEmit(const WaitingRoomSummaryLoading());
    final result = await _listWaitingRoom();
    result.fold(
      (failure) => safeEmit(WaitingRoomSummaryError(message: failure.message)),
      (entries) {
        if (entries.isEmpty) {
          safeEmit(
            const WaitingRoomSummaryLoaded(
              presentCount: 0,
              averageWaitMinutes: 0,
              longestWaitMinutes: 0,
            ),
          );
          return;
        }
        final waitMinutes =
            entries.map((entry) => entry.waitSoFar.inMinutes).toList();
        final averageWaitMinutes =
            (waitMinutes.reduce((a, b) => a + b) / waitMinutes.length).round();
        final longestWaitMinutes = waitMinutes.reduce(math.max);
        safeEmit(
          WaitingRoomSummaryLoaded(
            presentCount: entries.length,
            averageWaitMinutes: averageWaitMinutes,
            longestWaitMinutes: longestWaitMinutes,
          ),
        );
      },
    );
  }
}
