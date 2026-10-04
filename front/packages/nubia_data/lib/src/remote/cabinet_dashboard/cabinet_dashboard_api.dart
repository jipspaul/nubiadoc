import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_appointments/cabinet_appointments_dto.dart';
import 'package:nubia_data/src/remote/cabinet_dashboard/cabinet_dashboard_dto.dart';
import 'package:nubia_data/src/remote/medical_record/medical_record_dto.dart';
import 'package:nubia_data/src/remote/treatment_plans/treatment_plans_dto.dart';
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
  /// `practitionerId` restreint les compteurs/lignes du jour au praticien
  /// connecté (#6213 : `GET /cabinet/appointments` ne supporte pas de filtre
  /// `practitioner_id` côté serveur — contrairement à `/cabinet/agenda` — le
  /// champ étant tout de même renvoyé par item, on filtre côté client plutôt
  /// que d'agréger tout le cabinet sous « Ma journée »).
  Future<CabinetDashboardDto> getSummary({String? practitionerId}) async {
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

    final todayAppointments =
        _filterByPractitioner(results[0], practitionerId);
    final pendingConfirmations =
        _filterByPractitioner(results[3], practitionerId);

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
    final weeklyNoShowCount = results.skip(5).fold<int>(
          0,
          (s, dayResults) =>
              s + _filterByPractitioner(dayResults, practitionerId).length,
        );

    // #7116 : filtré par praticien comme todayAppointments/pendingConfirmations
    // ci-dessus — sinon le hero « Patient suivant » et waitingRoomCount
    // exposent la salle d'attente de tout le cabinet, y compris les
    // patients d'un confrère (POST .../start renvoie alors 403).
    final ownWaitingRoom = _filterByPractitioner(results[1], practitionerId);

    // #5045 : hero « Patient suivant » — celui qui attend depuis le plus
    // longtemps dans la salle d'attente déjà chargée ci-dessus (results[1]).
    // Réutilise WaitingRoomEntryDto (nom/motif/heure/attente, fallbacks déjà
    // durcis par #3782/#3861) plutôt que reparser le JSON brut ici.
    final waitingRoom = ownWaitingRoom
        .map((e) =>
            WaitingRoomEntryDto.fromJson(e as Map<String, dynamic>).toDomain())
        .toList()
      ..sort((a, b) => a.arrivedAt.compareTo(b.arrivedAt));
    final nextPatient = waitingRoom.isEmpty ? null : waitingRoom.first;

    // Durée prévue : jointure sur le RDV du jour correspondant
    // (todayAppointments), seul endroit où `duration_minutes` est exposé.
    //
    // #6576 : même jointure pour le nom complet du patient — `patientName`
    // de `nextPatient` vient de `/cabinet/waiting-room`, qui ne renvoie que
    // `patient_name_initials` ("MD"), d'où le héros affichant des initiales
    // alors que la liste « Journée » juste en dessous (alimentée par
    // `todayAppointments`, `patient_name` complet) affiche "Marc Dubois".
    int? nextPatientDurationMinutes;
    String? nextPatientFullName;
    if (nextPatient?.appointmentId != null) {
      for (final raw in todayAppointments) {
        final appointment =
            CabinetAppointmentDto.fromJson(raw as Map<String, dynamic>);
        if (appointment.id == nextPatient!.appointmentId) {
          nextPatientDurationMinutes = appointment.durationMinutes;
          if (appointment.patientName.isNotEmpty) {
            nextPatientFullName = appointment.patientName;
          }
          break;
        }
      }
    }

    // #7962 : pastilles « Alertes du dossier » / « Plan en cours » / «
    // Dernière visite » du hero — jointure sur le dossier médical du patient
    // qui attend (connu seulement une fois `nextPatient` résolu ci-dessus,
    // donc une 2ᵉ vague d'appels, pas le `Future.wait` initial). Lancés en
    // parallèle (chaque appel démarre avant le premier `await`) plutôt
    // qu'enchaînés séquentiellement.
    String? nextPatientAllergyLabel;
    int? nextPatientTreatmentPlanCents;
    DateTime? nextPatientLastVisitAt;
    final nextPatientId = nextPatient?.patientId;
    if (nextPatientId != null) {
      final medicalRecordFuture =
          _fetchObject('/cabinet/patients/$nextPatientId/medical-record');
      final treatmentPlansFuture =
          _fetchList('/cabinet/patients/$nextPatientId/treatment-plans');
      final patientFuture = _fetchObject('/cabinet/patients/$nextPatientId');

      final medicalRecord = await medicalRecordFuture;
      if (medicalRecord != null) {
        // Même libellé que l'encart « Alertes du dossier » de la vue
        // fauteuil (`patient_alerts_box.dart`) : "Allergie <substance>".
        for (final alert
            in MedicalRecordSummaryDto.fromJson(medicalRecord).medicalAlerts) {
          if (alert.kind == 'allergie') {
            nextPatientAllergyLabel = 'Allergie ${alert.label}';
            break;
          }
        }
      }

      final treatmentPlans = await treatmentPlansFuture;
      for (final raw in treatmentPlans) {
        final plan =
            TreatmentPlanDto.fromJson(raw as Map<String, dynamic>).toDomain();
        if (plan.status == 'in_progress') {
          nextPatientTreatmentPlanCents = plan.totalCents;
          break;
        }
      }

      final patient = await patientFuture;
      final lastVisitAt = patient?['last_visit_at'] as String?;
      if (lastVisitAt != null) {
        nextPatientLastVisitAt = DateTime.tryParse(lastVisitAt);
      }
    }

    return CabinetDashboardDto(
      todayAppointments: todayAppointments.length,
      waitingRoomCount: ownWaitingRoom.length,
      unreadMessages: unread,
      pendingConfirmations: pendingConfirmations.length,
      weeklyCompletedActs: weeklyCompletedActs,
      weeklyFeesCents: weeklyFeesCents,
      weeklyNoShowCount: weeklyNoShowCount,
      nextPatientName: nextPatientFullName ?? nextPatient?.patientName,
      nextPatientReason: nextPatient?.reason,
      nextPatientAppointmentTime: nextPatient?.appointmentTime,
      nextPatientDurationMinutes: nextPatientDurationMinutes,
      nextPatientWaitingMinutes: nextPatient?.waitSoFar.inMinutes,
      // #6241 : sans ces identifiants, le hero du tableau de bord ne peut
      // cibler ni le RDV (`POST .../start`) ni la fiche (`/patients/<id>`)
      // du patient qui attend.
      nextPatientAppointmentId: nextPatient?.appointmentId,
      nextPatientPatientId: nextPatient?.patientId,
      nextPatientAllergyLabel: nextPatientAllergyLabel,
      nextPatientTreatmentPlanCents: nextPatientTreatmentPlanCents,
      nextPatientLastVisitAt: nextPatientLastVisitAt,
    );
  }

  String _dateIso(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  List<dynamic> _filterByPractitioner(
    List<dynamic> items,
    String? practitionerId,
  ) {
    if (practitionerId == null) return items;
    return items
        .where((e) =>
            (e as Map<String, dynamic>)['practitioner_id'] == practitionerId)
        .toList();
  }

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

  /// Comme [_fetchList] mais pour un endpoint qui renvoie un objet unique
  /// (pas de clé `data`) — même isolation : un échec ponctuel (404/403/500)
  /// dégrade à `null` plutôt que de faire échouer tout le dashboard.
  Future<Map<String, dynamic>?> _fetchObject(String path) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(path);
      return response.data;
    } on DioException {
      return null;
    }
  }
}
