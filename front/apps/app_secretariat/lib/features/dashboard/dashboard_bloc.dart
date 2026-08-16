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
  final ListBookableSlotsUseCase _listBookableSlots;

  DashboardBloc({
    required GetCabinetAgendaUseCase getAgenda,
    required ListWaitingListUseCase listWaitingList,
    required ListBookableSlotsUseCase listBookableSlots,
  })  : _getAgenda = getAgenda,
        _listWaitingList = listWaitingList,
        _listBookableSlots = listBookableSlots,
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
      final weekStartDate = DateTime(
        weekStart.year,
        weekStart.month,
        weekStart.day,
      );

      final agendaResult = await _getAgenda(weekStartDate);
      final waitingResult = await _listWaitingList();
      final slotsResult = await _listBookableSlots(
        from: weekStartDate,
        to: weekStartDate.add(const Duration(days: 7)),
      );

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

          // #5383 : taux d'occupation par jour (Lun→Sam, cabinet fermé le
          // dimanche) — ratio créneaux occupés / total du jour, dérivé de
          // l'agenda semaine déjà chargé ci-dessus (aucun appel réseau
          // supplémentaire).
          final dailyOccupancyRates = List<double>.generate(6, (i) {
            final weekday = i + 1;
            final dayEntries =
                entries.where((e) => e.startsAt.weekday == weekday);
            final total = dayEntries.length;
            if (total == 0) return 0.0;
            final occupied =
                dayEntries.where((e) => !e.isFree && !e.isCancelled).length;
            return occupied / total;
          });
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

          // #5384 : la donnée `/bookable-slots` seule ne suffit pas — un
          // créneau peut y apparaître « ouvert » alors qu'un RDV du même
          // praticien le recouvre déjà dans l'agenda réel. Même exclusion
          // que le picker « Nouveau RDV » (agenda_page.dart : `bookableSlots`,
          // #3466) : on rapproche les créneaux bookables de la semaine du
          // planning déjà chargé plutôt que d'afficher le brut.
          final bookedForOverlap = booked.toList(growable: false);
          bool overlapsBooked(Slot s) {
            for (final e in bookedForOverlap) {
              if (e.practitionerId == s.practitionerId &&
                  s.startsAt.isBefore(e.endsAt) &&
                  e.startsAt.isBefore(s.endsAt)) {
                return true;
              }
            }
            return false;
          }

          final bookableSlots = slotsResult.getOrElse(() => const []);
          final freeSlotsThisWeek = bookableSlots
              .where((s) => s.isAvailable && !overlapsBooked(s))
              .toList(growable: false);
          final tomorrowStart = DateTime(now.year, now.month, now.day + 1);
          final tomorrowNoon = tomorrowStart.add(const Duration(hours: 12));
          final freeSlotsTomorrowMorningCount = freeSlotsThisWeek
              .where(
                (s) =>
                    !s.startsAt.isBefore(tomorrowStart) &&
                    s.startsAt.isBefore(tomorrowNoon),
              )
              .length;

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
              dailyOccupancyRates: dailyOccupancyRates,
              freeSlotsThisWeekCount: freeSlotsThisWeek.length,
              freeSlotsTomorrowMorningCount: freeSlotsTomorrowMorningCount,
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
