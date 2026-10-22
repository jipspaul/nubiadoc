import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'mes_rdv_event.dart';
import 'mes_rdv_state.dart';

class MesRdvBloc extends Bloc<MesRdvEvent, MesRdvState>
    with SafeEmitMixin<MesRdvState> {
  final GetUpcomingAppointmentsUseCase _getUpcoming;
  final GetAppointmentHistoryUseCase _getHistory;
  final CancelAppointmentUseCase _cancel;
  final CheckinAppointmentUseCase _checkin;

  // Taille de page (#8365) : bornée plutôt que de suivre les curseurs
  // jusqu'à épuisement avant le premier rendu — cf. doctrine #8279/#8297.
  static const _pageSize = 20;

  // Curseur de la dernière page d'historique chargée — mémorisé ici (et non
  // dans l'état) : détail de chargement interne, pas une information
  // affichée à l'écran.
  String? _historyCursor;

  MesRdvBloc({
    required GetUpcomingAppointmentsUseCase getUpcoming,
    required GetAppointmentHistoryUseCase getHistory,
    required CancelAppointmentUseCase cancel,
    required CheckinAppointmentUseCase checkin,
  })  : _getUpcoming = getUpcoming,
        _getHistory = getHistory,
        _cancel = cancel,
        _checkin = checkin,
        super(const MesRdvInitial()) {
    on<MesRdvLoadRequested>(_onLoad);
    on<MesRdvHistoryRequested>(_onHistoryLoad);
    on<MesRdvHistoryLoadMoreRequested>(_onHistoryLoadMore);
    on<MesRdvCancelRequested>(_onCancel);
    on<MesRdvCheckinRequested>(_onCheckin);
  }

  Future<void> _onLoad(
    MesRdvLoadRequested event,
    Emitter<MesRdvState> emit,
  ) async {
    _historyCursor = null;
    emit(const MesRdvLoading());
    try {
      final upcomingResult = await _getUpcoming();
      upcomingResult.fold(
        (failure) => safeEmit(MesRdvError(failure.message)),
        // La vue À venir s'affiche dès sa réponse ; l'historique se charge
        // paresseusement (voir _onHistoryLoad), sans bloquer ce rendu.
        (upcoming) => safeEmit(MesRdvLoaded(upcoming: upcoming, history: const [])),
      );
    } catch (_) {
      safeEmit(const MesRdvError('Erreur de chargement.'));
    }
  }

  Future<void> _onHistoryLoad(
    MesRdvHistoryRequested event,
    Emitter<MesRdvState> emit,
  ) async {
    final current = state;
    if (current is! MesRdvLoaded) return;
    if (current.historyLoading || current.historyLoaded) return;
    safeEmit(current.copyWith(historyLoading: true, clearHistoryError: true));
    try {
      final historyResult = await _getHistory(limit: _pageSize);
      historyResult.fold(
        (failure) => safeEmit(current.copyWith(
          historyLoading: false,
          historyError: failure.message,
        )),
        (page) {
          _historyCursor = page.nextCursor;
          safeEmit(current.copyWith(
            history: page.appointments,
            historyLoading: false,
            historyLoaded: true,
            historyHasMore: page.nextCursor != null,
          ));
        },
      );
    } catch (_) {
      safeEmit(current.copyWith(
        historyLoading: false,
        historyError: 'Erreur de chargement.',
      ));
    }
  }

  /// Charge la page d'historique suivante (#8365) — déclenché par le
  /// défilement proche du bas de la liste. No-op si une page est déjà en
  /// cours de chargement ou si la dernière page récupérée n'a pas de
  /// curseur suivant.
  Future<void> _onHistoryLoadMore(
    MesRdvHistoryLoadMoreRequested event,
    Emitter<MesRdvState> emit,
  ) async {
    final current = state;
    if (current is! MesRdvLoaded ||
        !current.historyHasMore ||
        current.historyLoadingMore ||
        _historyCursor == null) {
      return;
    }
    safeEmit(current.copyWith(historyLoadingMore: true));
    try {
      final historyResult =
          await _getHistory(limit: _pageSize, cursor: _historyCursor);
      historyResult.fold(
        (failure) => safeEmit(current.copyWith(historyLoadingMore: false)),
        (page) {
          _historyCursor = page.nextCursor;
          safeEmit(current.copyWith(
            history: [...current.history, ...page.appointments],
            historyHasMore: page.nextCursor != null,
            historyLoadingMore: false,
          ));
        },
      );
    } catch (_) {
      safeEmit(current.copyWith(historyLoadingMore: false));
    }
  }

  Future<void> _onCancel(
    MesRdvCancelRequested event,
    Emitter<MesRdvState> emit,
  ) async {
    final current = state;
    if (current is! MesRdvLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    try {
      final result = await _cancel(event.appointment);
      await result.fold(
        (failure) async => safeEmit(current.copyWith(
          actionInProgress: false,
          actionError: failure.message,
        )),
        (_) async => _onLoad(const MesRdvLoadRequested(), emit),
      );
    } catch (_) {
      safeEmit(current.copyWith(
          actionInProgress: false, actionError: 'Erreur inattendue.'));
    }
  }

  Future<void> _onCheckin(
    MesRdvCheckinRequested event,
    Emitter<MesRdvState> emit,
  ) async {
    final current = state;
    if (current is! MesRdvLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    try {
      final result = await _checkin(event.appointmentId);
      await result.fold(
        (failure) async => safeEmit(current.copyWith(
          actionInProgress: false,
          actionError: failure.message,
        )),
        (_) async => _onLoad(const MesRdvLoadRequested(), emit),
      );
    } catch (_) {
      safeEmit(current.copyWith(
          actionInProgress: false, actionError: 'Erreur inattendue.'));
    }
  }
}
