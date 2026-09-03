/// Kind of authenticated principal, mirroring the backend JWT `kind` claim.
enum UserKind { patient, pro }

/// Professional role within a cabinet, mirroring the backend `role` claim.
///
/// Drives UI feature-gating in the pro apps. The secretariat app must never
/// expose clinical surfaces — see [ProRole.secretary].
enum ProRole { admin, practitioner, secretary, pharmacist, nurse, unknown }

ProRole proRoleFromString(String? value) {
  switch (value) {
    case 'admin':
      return ProRole.admin;
    case 'practitioner':
      return ProRole.practitioner;
    case 'secretary':
      return ProRole.secretary;
    case 'pharmacist':
      return ProRole.pharmacist;
    case 'nurse':
      return ProRole.nurse;
    default:
      return ProRole.unknown;
  }
}

/// The authenticated session, derived from `GET /v1/me`.
///
/// Shared across the three apps. Patient sessions carry [accountId]; pro
/// sessions carry [role] and [cabinetId].
class AuthSession {
  const AuthSession({
    required this.kind,
    required this.userId,
    this.accountId,
    this.role = ProRole.unknown,
    this.cabinetId,
    this.practitionerId,
    this.displayName,
    this.contextLabel,
  });

  final UserKind kind;
  final String userId;

  /// Patient-only: the patient account id.
  final String? accountId;

  /// Pro-only: role within the active cabinet.
  final ProRole role;

  /// Pro-only: the active cabinet id.
  final String? cabinetId;

  /// Pro-only: the `practitioner` entity id for this user in the active
  /// cabinet, distinct from [userId] (`practitioner.user_id` references it,
  /// cf. #6251) — `null` when the user has no practitioner entity there
  /// (secretary, non-practitioner admin).
  final String? practitionerId;

  final String? displayName;

  /// Human-readable context label shown in app banners, e.g.
  /// "Secrétariat "Dents & Co" — Établissement: Agence Lyon".
  /// Null when no context is available.
  final String? contextLabel;

  bool get isPro => kind == UserKind.pro;
  bool get isPatient => kind == UserKind.patient;

  /// True when this session is allowed to see clinical content.
  /// Secretaries are administrative-only.
  bool get canAccessClinical =>
      isPro && (role == ProRole.admin || role == ProRole.practitioner);

  bool get isAdmin => role == ProRole.admin;
}
