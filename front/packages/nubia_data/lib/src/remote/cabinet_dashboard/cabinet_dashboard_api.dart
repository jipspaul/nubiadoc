import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_appointments/cabinet_appointments_dto.dart';
import 'package:nubia_data/src/remote/cabinet_dashboard/cabinet_dashboard_dto.dart';
import 'package:nubia_data/src/remote/waiting_room/waiting_room_dto.dart';

class CabinetDashboardApi {
  final Dio _dio;

  CabinetDashboardApi(ApiClient client) : _dio = client.dio;

  /// Agrège les compteurs depuis les endpoints réels car GET /cabinet/dashboard
  /// n'est pas encore déployé (404). Tous les appels sont lancés en parallèle.
  ///
  /// Chaque appel est isolé : un échec ponctuel sur l'un d'eux (404/500/timeout)
  /// dégrade son compteur à 0 au lieu de faire échouer tout le dashboard
  /// (cf. #3225 — un seul sous-appel en erreur affichait un écran d'erreur
  /// générique alors que les autres compteurs étaient disponibles).
  ///
  /// #6037 : les compteurs hebdomadaires (`weekly*`) étaient codés en dur à
  /// 0 en attendant `GET /cabinet/dashboard`, alors que les endpoints
  /// existants (`/cabinet/stats/activity`, #4079) et `/cabinet/appointments`
  /// (déjà utilisé ci-dessus pour les compteurs du jour) permettent de les
  /// dériver honnêtement, même principe que le reste de cette classe.
  Future<CabinetDashboardDto> getSummary() async {
    final today = DateTime.now();
    final todayIso = _dateIso(today);

    final weekMonday = today.subtract(Duration(days: today.weekday - 1));
    final weekFriday = weekMonday.add(const Duration(days: 4));

    // RDV non honorés : bornés aux jours ouvrés déjà écoulés (lundi ->
    // aujourd'hui, au plus vendredi) — un no-show suppose un RDV déjà passé,
    // interroger les jours futurs ne renverrait toujours rien.
    final elapsedWeekdays = <String>[
      for (var day = weekMonday;
          !day.isAfter(weekFriday) && !day.isAfter(today);
          day = day.add(const Duration(days: 1)))
        _dateIso(day),
    ];

    final results = await Future.wait([
      _fetchList('/cabinet/appointments', queryParameters: {'date': todayIso}),
      _fetchList('/cabinet/waiting-room'),
      _fetchList('/cabinet/conversations'),
      // #3861 : sans `date`, comptait TOUS les requested toutes dates
      // confondues — RDV périmés de 2021/2025 inclus (105 au lieu de 11
      // réellement actionnables aujourd'hui). Même borne que le 1er appel
      // (`todayIso`), cohérent avec le correctif du dashboard secrétariat
      // (#3855) qui exclut aussi les RDV non pertinents du jour.
      _fetchList(
        '/cabinet/appointments',
        queryParameters: {'status': 'requested', 'date': todayIso},
      ),
      // Actes réalisés + honoraires (encaissés et engagés) lundi->vendredi.
      _fetchList(
        '/cabinet/stats/activity',
        queryParameters: {
          'from': _dateIso(weekMonday),
          'to': _dateIso(weekFriday),
        },
      ),
      for (final day in elapsedWeekdays)
        _fetchList(
          '/cabinet/appointments',
          queryParameters: {'status': 'no_show', 'date': day},
        ),
    ]);

    final convs = results[2];
    final unread = convs.fold<int>(
      0,
      (s, c) => s + ((c as Map<String, dynamic>)['unread_count'] as int? ?? 0),
    );

    final activityStats = results[4];
    final weeklyCompletedActs = activityStats.fold<int>(
      0,
      (s, item) =>
          s + (((item as Map<String, dynamic>)['act_count'] as num?) ?? 0).toInt(),
    );
    final weeklyFeesCents = activityStats.fold<int>(
      0,
      (s, item) =>
          s +
          (((item as Map<String, dynamic>)['total_amount_cents'] as num?) ?? 0)
              .toInt(),
    );
    final weeklyNoShowCount = results
        .skip(5)
        .fold<int>(0, (s, dayResults) => s + dayResults.length);

    // #5045 : hero « Patient suivant » — celui qui attend depuis le plus
    // longtemps dans la salle d'attente déjà chargée ci-dessus (results[1]).
    // Réutilise WaitingRoomEntryDto (nom/motif/heure/attente, fallbacks déjà
    // durcis par #3782/#3861) plutôt que reparser le JSON brut ici.
    final waitingRoom = results[1]
        .map((e) =>
            WaitingRoomEntryDto.fromJson(e as Map<String, dynamic>).toDomain())
        .toList()
      ..sort((a, b) => a.arrivedAt.compareTo(b.arrivedAt));
    final nextPatient = waitingRoom.isEmpty ? null : waitingRoom.first;

    // Durée prévue : jointure sur le RDV du jour correspondant (results[0]),
    // seul endroit où `duration_minutes` est exposé.
    int? nextPatientDurationMinutes;
    if (nextPatient?.appointmentId != null) {
      for (final raw in results[0]) {
        final appointment =
            CabinetAppointmentDto.fromJson(raw as Map<String, dynamic>);
        if (appointment.id == nextPatient!.appointmentId) {
          nextPatientDurationMinutes = appointment.durationMinutes;
          break;
        }
      }
    }

    return CabinetDashboardDto(
      todayAppointments: results[0].length,
      waitingRoomCount: results[1].length,
      unreadMessages: unread,
      pendingConfirmations: results[3].length,
      weeklyCompletedActs: weeklyCompletedActs,
      weeklyFeesCents: weeklyFeesCents,
      weeklyNoShowCount: weeklyNoShowCount,
      nextPatientName: nextPatient?.patientName,
      nextPatientReason: nextPatient?.reason,
      nextPatientAppointmentTime: nextPatient?.appointmentTime,
      nextPatientDurationMinutes: nextPatientDurationMinutes,
      nextPatientWaitingMinutes: nextPatient?.waitSoFar.inMinutes,
      // Allergie / plan de traitement / dernière visite : pas encore exposés
      // par ces endpoints — cf. commentaire de classe de [ProDashboardSummary].
      nextPatientAllergyLabel: null,
      nextPatientTreatmentPlanCents: null,
      nextPatientLastVisitAt: null,
    );
  }

  String _dateIso(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<List<dynamic>> _fetchList(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: queryParameters,
      );
      return response.data?['data'] as List? ?? const [];
    } on DioException {
      return const [];
    }
  }
}
