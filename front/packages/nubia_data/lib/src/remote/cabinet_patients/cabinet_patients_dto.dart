import 'package:nubia_domain/src/entities/cabinet_patient.dart';

class CabinetPatientDto {
  final String id;
  final String cabinetId;
  final String firstName;
  final String lastName;
  final String? birthDate;
  final String? email;
  final String? phone;
  final String? socialSecurityNumber;
  final String? lastVisitAt;
  final String createdAt;
  final int? balanceDueCents;
  final int? noShowCount;
  final List<GuardianshipLink>? guardians;
  final List<GuardianshipLink>? dependents;
  final bool? hasActiveAlerts;
  final bool? hasUpcomingAppointment;

  const CabinetPatientDto({
    required this.id,
    required this.cabinetId,
    required this.firstName,
    required this.lastName,
    this.birthDate,
    this.email,
    this.phone,
    this.socialSecurityNumber,
    this.lastVisitAt,
    required this.createdAt,
    this.balanceDueCents,
    this.noShowCount,
    this.guardians,
    this.dependents,
    this.hasActiveAlerts,
    this.hasUpcomingAppointment,
  });

  factory CabinetPatientDto.fromJson(Map<String, dynamic> json) {
    // `GET /v1/cabinet/patients/:id` imbrique les coordonnées sous `contact`
    // (`api/src/clinical.rs` `PatientAdminSection`, colonne JSONB `contact` :
    // "email, tel, adresse") — jamais de clés top-level `phone`/`email`. Le
    // DTO lisait des clés plates absentes ⇒ toujours null ⇒ ligne Téléphone/
    // E-mail masquée côté fiche patient praticien, alors que la donnée existe
    // (#3832). N° sécu : aucun champ backend ne le porte nulle part (ni
    // top-level ni dans `contact`) — reste volontairement non lu ici tant
    // qu'aucune donnée réelle n'existe à mapper.
    final contact = json['contact'] as Map<String, dynamic>? ?? const {};
    List<GuardianshipLink>? parseLinks(String key) {
      final raw = json[key] as List<dynamic>?;
      if (raw == null) return null;
      return raw
          .map((e) => e as Map<String, dynamic>)
          .map((e) => GuardianshipLink(
                accountId: e['account_id'] as String,
                firstName: e['first_name'] as String,
                lastName: e['last_name'] as String,
                relationship: e['relationship'] as String,
              ))
          .toList();
    }

    return CabinetPatientDto(
      id: json['id'] as String,
      cabinetId: (json['cabinet_id'] as String?) ?? '',
      firstName: (json['first_name'] as String?) ?? '',
      lastName: (json['last_name'] as String?) ?? '',
      birthDate: json['birth_date'] as String?,
      email: (contact['email'] as String?) ?? (json['email'] as String?),
      phone: (contact['tel'] as String?) ?? (json['phone'] as String?),
      socialSecurityNumber: json['social_security_number'] as String?,
      lastVisitAt: json['last_visit_at'] as String?,
      createdAt: json['created_at'] as String,
      // Présent sur `GET /cabinet/patients/:id` (#4044) et, depuis #5112,
      // sur la liste paginée `GET /cabinet/patients` — reste nullable
      // (best-effort) dans les deux cas.
      balanceDueCents: json['balance_due_cents'] as int?,
      // Idem (#4090, #5112).
      noShowCount: json['no_show_count'] as int?,
      // Idem (#4091) — toujours des tableaux (jamais absents) sur le
      // détail ; `null` seulement si la clé n'existe pas du tout dans la
      // réponse (liste paginée).
      guardians: parseLinks('guardians'),
      dependents: parseLinks('dependents'),
      // Filtres rapides secrétariat (#5118) — mêmes conditions de
      // disponibilité que balanceDueCents/noShowCount ci-dessus.
      hasActiveAlerts: json['has_active_alerts'] as bool?,
      hasUpcomingAppointment: json['has_upcoming_appointment'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'cabinet_id': cabinetId,
        'first_name': firstName,
        'last_name': lastName,
        if (birthDate != null) 'birth_date': birthDate,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (socialSecurityNumber != null)
          'social_security_number': socialSecurityNumber,
        'created_at': createdAt,
      };

  CabinetPatient toDomain() => CabinetPatient(
        id: id,
        cabinetId: cabinetId,
        firstName: firstName,
        lastName: lastName,
        birthDate: birthDate != null ? DateTime.parse(birthDate!) : null,
        email: email,
        phone: phone,
        socialSecurityNumber: socialSecurityNumber,
        lastVisitAt: lastVisitAt != null ? DateTime.parse(lastVisitAt!) : null,
        createdAt: DateTime.parse(createdAt),
        balanceDueCents: balanceDueCents,
        noShowCount: noShowCount,
        guardians: guardians,
        dependents: dependents,
        hasActiveAlerts: hasActiveAlerts,
        hasUpcomingAppointment: hasUpcomingAppointment,
      );

  factory CabinetPatientDto.fromDomain(CabinetPatient p) => CabinetPatientDto(
        id: p.id,
        cabinetId: p.cabinetId,
        firstName: p.firstName,
        lastName: p.lastName,
        birthDate: p.birthDate?.toIso8601String(),
        email: p.email,
        phone: p.phone,
        socialSecurityNumber: p.socialSecurityNumber,
        lastVisitAt: p.lastVisitAt?.toIso8601String(),
        createdAt: p.createdAt.toIso8601String(),
      );
}
