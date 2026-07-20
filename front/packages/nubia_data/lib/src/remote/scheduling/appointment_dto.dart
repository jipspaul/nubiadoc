import 'package:nubia_domain/src/entities/appointment.dart';

class AppointmentDto {
  final String id;
  final String cabinetId;
  final String practitionerName;
  final String practitionerSpecialty;
  final String startsAt;
  final int durationMinutes;
  final String motif;
  final String status;
  final String type;
  final String? cabinetAddress;
  final String? cabinetPhone;
  final String practitionerId;

  const AppointmentDto({
    required this.id,
    required this.cabinetId,
    required this.practitionerName,
    required this.practitionerSpecialty,
    required this.startsAt,
    required this.durationMinutes,
    required this.motif,
    required this.status,
    required this.type,
    this.cabinetAddress,
    this.cabinetPhone,
    this.practitionerId = '',
  });

  factory AppointmentDto.fromJson(Map<String, dynamic> json) {
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
    final provider = json['provider'] as Map<String, dynamic>?;
    final practitionerName = (provider?['display_name'] as String?) ??
        (json['practitioner_name'] as String?) ??
        '';
    final practitionerId = (provider?['id'] as String?) ??
        (json['practitioner_id'] as String?) ??
        (json['provider_id'] as String?) ??
        '';
    // #3825 : l'API sérialise la spécialité imbriquée sous `provider.specialty`
    // (jamais en `practitioner_specialty` de premier niveau, clé conservée en
    // repli défensif seulement) — la lire au mauvais endroit laissait le champ
    // vide en permanence (séparateur « · » pendant sur 3 écrans patient).
    final practitionerSpecialty = (provider?['specialty'] as String?) ??
        (json['practitioner_specialty'] as String?) ??
        '';
    return AppointmentDto(
      id: json['id'] as String,
      cabinetId: json['cabinet_id'] as String? ?? '',
      practitionerName: practitionerName,
      practitionerSpecialty: practitionerSpecialty,
      startsAt: startsAt,
      durationMinutes: durationMinutes,
      motif: json['motif'] as String? ?? '',
      status: json['status'] as String,
      type: json['type'] as String? ?? 'in_person',
      cabinetAddress: json['cabinet_address'] as String?,
      cabinetPhone: json['cabinet_phone'] as String?,
      practitionerId: practitionerId,
    );
  }

  Appointment toDomain() => Appointment(
        id: id,
        cabinetId: cabinetId,
        practitionerName: practitionerName,
        practitionerSpecialty: practitionerSpecialty,
        startsAt: DateTime.parse(startsAt),
        duration: Duration(minutes: durationMinutes),
        motif: motif,
        status: _parseStatus(status),
        type: type == 'teleconsult'
            ? AppointmentType.teleconsult
            : AppointmentType.inPerson,
        cabinetAddress: cabinetAddress,
        cabinetPhone: cabinetPhone,
        practitionerId: practitionerId,
      );

  // #3804 : le back envoie 'done' (jamais 'completed') et distingue
  // checked_in/in_progress (CHECK constraint appointment.status,
  // db/migrations/0005_scheduling.sql) — un statut non mappé ici retombait
  // silencieusement sur `requested`, faisant apparaître un RDV terminé ou
  // en cours comme une simple demande en attente.
  static AppointmentStatus _parseStatus(String value) {
    switch (value) {
      case 'requested':
        return AppointmentStatus.requested;
      case 'confirmed':
        return AppointmentStatus.confirmed;
      case 'checked_in':
        return AppointmentStatus.checkedIn;
      case 'in_progress':
        return AppointmentStatus.inProgress;
      case 'cancelled':
        return AppointmentStatus.cancelled;
      case 'done':
      case 'completed':
        return AppointmentStatus.completed;
      case 'no_show':
        return AppointmentStatus.noShow;
      default:
        return AppointmentStatus.requested;
    }
  }
}
