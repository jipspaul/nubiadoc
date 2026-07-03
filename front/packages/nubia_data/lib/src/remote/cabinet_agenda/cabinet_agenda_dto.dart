import 'package:nubia_domain/src/entities/agenda_entry.dart';

class AgendaEntryDto {
  final String id;
  final String cabinetId;
  final String practitionerId;
  final String practitionerName;
  final String startsAt;
  final String endsAt;
  final String? patientId;
  final String? patientName;
  final String? motif;
  final bool isFree;

  const AgendaEntryDto({
    required this.id,
    required this.cabinetId,
    required this.practitionerId,
    required this.practitionerName,
    required this.startsAt,
    required this.endsAt,
    this.patientId,
    this.patientName,
    this.motif,
    required this.isFree,
  });

  factory AgendaEntryDto.fromJson(Map<String, dynamic> json) => AgendaEntryDto(
        id: json['id'] as String,
        cabinetId: json['cabinet_id'] as String,
        practitionerId: json['practitioner_id'] as String,
        practitionerName: json['practitioner_name'] as String,
        startsAt: json['starts_at'] as String,
        endsAt: json['ends_at'] as String,
        patientId: json['patient_id'] as String?,
        patientName: json['patient_name'] as String?,
        motif: json['motif'] as String?,
        isFree: (json['is_free'] as bool?) ?? true,
      );

  /// Construit une entrée depuis un `AgendaSlot` du back
  /// (`{ id, practitioner_id, starts_at, ends_at, status, motif_admin }`),
  /// en résolvant le nom du praticien via la table renvoyée à côté.
  factory AgendaEntryDto.fromSlotJson(
    Map<String, dynamic> json, {
    required Map<String, String> practitionerNames,
  }) {
    final practitionerId = json['practitioner_id'] as String;
    final status = (json['status'] as String?) ?? '';
    return AgendaEntryDto(
      id: json['id'] as String,
      // Le back ne renvoie pas cabinet_id sur l'agenda (scopé JWT côté serveur).
      cabinetId: (json['cabinet_id'] as String?) ?? '',
      practitionerId: practitionerId,
      practitionerName: practitionerNames[practitionerId] ?? '',
      startsAt: json['starts_at'] as String,
      endsAt: json['ends_at'] as String,
      patientId: json['patient_id'] as String?,
      patientName: json['patient_name'] as String?,
      // Secrétariat : seul le motif administratif est exposé (R.4127-72).
      motif: json['motif_admin'] as String? ?? json['motif'] as String?,
      // Les entrées de l'agenda sont des rendez-vous ; libre seulement si le
      // statut l'indique explicitement.
      isFree: status == 'free' || status == 'open' || status == 'available',
    );
  }

  Map<String, dynamic> toJson() => {
        'practitioner_id': practitionerId,
        'starts_at': startsAt,
        'ends_at': endsAt,
        if (patientId != null) 'patient_id': patientId,
        if (motif != null) 'motif': motif,
      };

  AgendaEntry toDomain() => AgendaEntry(
        id: id,
        cabinetId: cabinetId,
        practitionerId: practitionerId,
        practitionerName: practitionerName,
        startsAt: DateTime.parse(startsAt),
        endsAt: DateTime.parse(endsAt),
        patientId: patientId,
        patientName: patientName,
        motif: motif,
        isFree: isFree,
      );
}
