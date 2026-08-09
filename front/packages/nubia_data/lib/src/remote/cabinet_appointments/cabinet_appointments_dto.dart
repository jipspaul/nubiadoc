import 'package:nubia_domain/src/entities/cabinet_appointment.dart';

class CabinetAppointmentDto {
  final String id;
  final String cabinetId;
  final String patientId;
  final String patientName;
  final String practitionerId;
  final String practitionerName;
  final String startsAt;
  final int durationMinutes;
  final String motif;
  final String status;

  const CabinetAppointmentDto({
    required this.id,
    required this.cabinetId,
    required this.patientId,
    required this.patientName,
    required this.practitionerId,
    required this.practitionerName,
    required this.startsAt,
    required this.durationMinutes,
    required this.motif,
    required this.status,
  });

  factory CabinetAppointmentDto.fromJson(Map<String, dynamic> json) {
    final startsAt = json['starts_at'] as String;
    final endsAt = json['ends_at'] as String?;
    final int durationMinutes;
    if (json['duration_minutes'] != null) {
      durationMinutes = (json['duration_minutes'] as num).toInt();
    } else if (endsAt != null) {
      durationMinutes =
          DateTime.parse(endsAt).difference(DateTime.parse(startsAt)).inMinutes;
    } else {
      durationMinutes = 0;
    }
    return CabinetAppointmentDto(
      id: json['id'] as String,
      cabinetId: json['cabinet_id'] as String? ?? '',
      patientId: json['patient_id'] as String,
      patientName: json['patient_name'] as String? ?? '',
      practitionerId: json['practitioner_id'] as String,
      // #4664 : `GET /cabinet/appointments` n'émet JAMAIS `practitioner_name`
      // (seulement `practitioner_id`) — repli `provider.display_name` conservé
      // au cas où une réponse imbriquée serait un jour introduite (même
      // pattern que le fix patient #3825). La résolution effective par le
      // roster du cabinet se fait ensuite dans
      // `CabinetAppointmentsRepositoryImpl` (via `CabinetAgendaRepository.
      // listPractitioners`), ce DTO reste une lecture fidèle du JSON.
      practitionerName: (json['practitioner_name'] as String?) ??
          ((json['provider'] as Map<String, dynamic>?)?['display_name']
              as String?) ??
          '',
      startsAt: startsAt,
      durationMinutes: durationMinutes,
      motif:
          (json['motif_admin'] as String?) ?? (json['motif'] as String?) ?? '',
      status: json['status'] as String,
    );
  }

  /// Réponse de `POST /cabinet/appointments/:id/confirm`.
  ///
  /// Le back ne renvoie que `{ appointment_id, status }` (et non le RDV
  /// complet). On construit un DTO minimal pour éviter une erreur de décodage :
  /// seuls `id` et `status` sont pertinents, l'appelant se contente de
  /// recharger l'agenda après confirmation.
  factory CabinetAppointmentDto.fromConfirmResponse(Map<String, dynamic> json) {
    return CabinetAppointmentDto(
      id: (json['appointment_id'] as String?) ?? (json['id'] as String?) ?? '',
      cabinetId: '',
      patientId: '',
      patientName: '',
      practitionerId: '',
      practitionerName: '',
      startsAt: DateTime.now().toIso8601String(),
      durationMinutes: 0,
      motif: '',
      status: (json['status'] as String?) ?? 'confirmed',
    );
  }

  Map<String, dynamic> toJson() => {
        'patient_id': patientId,
        'practitioner_id': practitionerId,
        'starts_at': startsAt,
        'duration_minutes': durationMinutes,
        'motif': motif,
        'status': status,
      };

  CabinetAppointment toDomain() => CabinetAppointment(
        id: id,
        cabinetId: cabinetId,
        patientId: patientId,
        patientName: patientName,
        practitionerId: practitionerId,
        practitionerName: practitionerName,
        startsAt: DateTime.parse(startsAt),
        duration: Duration(minutes: durationMinutes),
        motif: motif,
        status: _parseStatus(status),
      );

  // #3826 : le back envoie 'done' (jamais 'completed', statut inexistant côté
  // DB — db/migrations/0010_hifi_extensions.sql) — un RDV terminé retombait
  // silencieusement sur `requested` (pill « En attente »), indistinguable
  // d'un RDV réellement en attente de confirmation. Même famille que #3804
  // (appointment_dto.dart, app patient), fichier distinct (cabinet_appointments_dto.dart,
  // apps secrétariat/praticien) — un fix de l'un ne corrige pas l'autre.
  static CabinetAppointmentStatus _parseStatus(String value) {
    switch (value) {
      case 'requested':
        return CabinetAppointmentStatus.requested;
      case 'confirmed':
        return CabinetAppointmentStatus.confirmed;
      case 'in_progress':
        return CabinetAppointmentStatus.inProgress;
      case 'done':
      case 'completed':
        return CabinetAppointmentStatus.completed;
      case 'cancelled':
        return CabinetAppointmentStatus.cancelled;
      case 'no_show':
        return CabinetAppointmentStatus.noShow;
      default:
        return CabinetAppointmentStatus.requested;
    }
  }
}
