import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'dashboard_event.dart';
import 'dashboard_state.dart';

/// Tableau de bord secrétariat : compteurs réels dérivés de l'agenda du
/// cabinet et de la liste d'attente (#3362 — les valeurs étaient codées à 0
/// en dur, le dashboard contredisait l'agenda).
///
/// Pas d'endpoint agrégé côté API : on compose les endpoints existants.
class DashboardBloc extends Bloc<DashboardEvent, DashboardState>
    with SafeEmitMixin<DashboardState> {
  final GetCabinetAgendaUseCase _getAgenda;
  final ListWaitingListUseCase _listWaitingList;

  DashboardBloc({
    required GetCabinetAgendaUseCase getAgenda,
    required ListWaitingListUseCase listWaitingList,
  }) : _getAgenda = getAgenda,
       _listWaitingList = listWaitingList,
       super(const DashboardInitial()) {
    on<DashboardLoadRequested>(_onLoad);
  }

  Future<void> _onLoad(
    DashboardLoadRequested event,
    Emitter<DashboardState> emit,
  ) async {
    emit(const DashboardLoading());
    try {
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));

      final agendaResult = await _getAgenda(
        DateTime(weekStart.year, weekStart.month, weekStart.day),
      );
      final waitingResult = await _listWaitingList();

      // L'agenda est la source des deux premiers compteurs ; la liste
      // d'attente est best-effort (0 si l'appel échoue, pas d'écran d'erreur
      // pour un compteur secondaire).
      agendaResult.fold(
        (failure) => safeEmit(DashboardError(message: failure.message)),
        (entries) {
          // #3855 : `booked` (tout créneau non-libre) comptait aussi les RDV
          // confirmed/done/no_show/cancelled comme « à confirmer » — un
          // secrétaire voyait 69 « demandes à confirmer » dont 13 annulés et
          // 22 terminés, au lieu des 23 réellement en attente (status
          // 'requested'). Même exclusion des annulés que l'écran Agenda
          // (agenda_page.dart : `!isFree && status != 'cancelled'`).
          final booked = entries.where((e) => !e.isFree && !e.isCancelled);
          final todayCount = booked
              .where(
                (e) =>
                    e.startsAt.year == now.year &&
                    e.startsAt.month == now.month &&
                    e.startsAt.day == now.day,
              )
              .length;
          final pendingCount = entries
              .where(
                (e) =>
                    e.isPending &&
                    e.startsAt.year == now.year &&
                    e.startsAt.month == now.month &&
                    e.startsAt.day == now.day,
              )
              .length;
          final waitingCount = waitingResult.fold(
            (_) => 0,
            (list) => list.length,
          );

          final todayBooked = booked.where(
            (e) =>
                e.startsAt.year == now.year &&
                e.startsAt.month == now.month &&
                e.startsAt.day == now.day,
          );
          final byPractitioner = <String, List<AgendaEntry>>{};
          for (final e in todayBooked) {
            byPractitioner.putIfAbsent(e.practitionerId, () => []).add(e);
          }
          final practitionersToday = byPractitioner.values.map((entries) {
            final isInConsultation = entries.any(
              (e) => !now.isBefore(e.startsAt) && now.isBefore(e.endsAt),
            );
            final lastEndsAt = entries
                .map((e) => e.endsAt)
                .reduce((a, b) => a.isAfter(b) ? a : b);
            return PractitionerToday(
              practitionerId: entries.first.practitionerId,
              practitionerName: entries.first.practitionerName,
              appointmentCount: entries.length,
              isInConsultation: isInConsultation,
              lastAppointmentEndsAt: lastEndsAt,
            );
          }).toList()
            ..sort(
              (a, b) => a.practitionerName.compareTo(b.practitionerName),
            );

          safeEmit(
            DashboardLoaded(
              todayCount: todayCount,
              pendingCount: pendingCount,
              waitingCount: waitingCount,
              practitionersToday: practitionersToday,
            ),
          );
        },
      );
    } catch (_) {
      safeEmit(
        const DashboardError(
          message: 'Impossible de charger le tableau de bord.',
        ),
      );
    }
  }
}
