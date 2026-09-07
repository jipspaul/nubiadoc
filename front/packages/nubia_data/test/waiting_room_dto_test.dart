import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/nubia_data.dart';

void main() {
  group('WaitingRoomEntryDto', () {
    // Régression #3782 : GET /v1/cabinet/waiting-room ne renvoie jamais `id`
    // (seulement appointment_id, patient_name_initials, checkin_at,
    // wait_minutes, status) — un cast dur sur `json['id']` faisait échouer
    // le décodage de CHAQUE entrée dès qu'un patient était en salle
    // d'attente (écran d'erreur plein écran, fonctionnalité coeur cassée).
    test(
        'fromJson retombe sur appointment_id quand id est absent (payload réel API)',
        () {
      final dto = WaitingRoomEntryDto.fromJson({
        'appointment_id': 'd4077170-b80c-4e6b-989e-a1c9877d4617',
        'patient_name_initials': 'Marc Dubois',
        'checkin_at': '2026-07-13T22:48:48.220795+00:00',
        'wait_minutes': 26,
        'status': 'checked_in',
      });
      expect(dto.id, 'd4077170-b80c-4e6b-989e-a1c9877d4617');
      expect(dto.appointmentId, 'd4077170-b80c-4e6b-989e-a1c9877d4617');
      expect(dto.patientName, 'Marc Dubois');
      expect(dto.estimatedWaitMinutes, 26);
    });

    // #6611 : les maquettes design-v2 veulent le nom complet dans le héros,
    // la file et le bouton d'appel — `patient_name_initials` reste réservé à
    // la pastille avatar. L'API renvoie désormais les deux champs.
    test('fromJson préfère patient_name (nom complet) à patient_name_initials',
        () {
      final dto = WaitingRoomEntryDto.fromJson({
        'appointment_id': 'd4077170-b80c-4e6b-989e-a1c9877d4617',
        'patient_name': 'Marc Dubois',
        'patient_name_initials': 'MD',
        'checkin_at': '2026-07-13T22:48:48.220795+00:00',
        'wait_minutes': 26,
        'status': 'checked_in',
      });
      expect(dto.patientName, 'Marc Dubois');
    });

    test('fromJson retombe sur patient_name_initials si patient_name absent',
        () {
      final dto = WaitingRoomEntryDto.fromJson({
        'appointment_id': 'd4077170-b80c-4e6b-989e-a1c9877d4617',
        'patient_name_initials': 'MD',
        'checkin_at': '2026-07-13T22:48:48.220795+00:00',
        'wait_minutes': 26,
        'status': 'checked_in',
      });
      expect(dto.patientName, 'MD');
    });

    test('fromJson préfère encore id si présent (compat future)', () {
      final dto = WaitingRoomEntryDto.fromJson({
        'id': 'entry-id-explicite',
        'appointment_id': 'appt-id-different',
      });
      expect(dto.id, 'entry-id-explicite');
    });

    // #5172 : sous-titre salle d'attente = motif + heure de RDV.
    test('fromJson mappe motif/starts_at quand présents', () {
      final dto = WaitingRoomEntryDto.fromJson({
        'appointment_id': 'd4077170-b80c-4e6b-989e-a1c9877d4617',
        'patient_name_initials': 'MD',
        'checkin_at': '2026-07-13T22:48:48.220795+00:00',
        'wait_minutes': 26,
        'status': 'checked_in',
        'motif': 'Détartrage',
        'starts_at': '2026-07-13T10:00:00+00:00',
      });
      expect(dto.reason, 'Détartrage');
      expect(dto.appointmentTime, '2026-07-13T10:00:00+00:00');
      final domain = dto.toDomain();
      expect(domain.reason, 'Détartrage');
      expect(domain.appointmentTime, DateTime.parse('2026-07-13T10:00:00+00:00'));
    });

    test('fromJson tolère motif/starts_at absents (pas de crash)', () {
      final dto = WaitingRoomEntryDto.fromJson({
        'appointment_id': 'd4077170-b80c-4e6b-989e-a1c9877d4617',
        'patient_name_initials': 'MD',
        'checkin_at': '2026-07-13T22:48:48.220795+00:00',
        'wait_minutes': 26,
        'status': 'checked_in',
      });
      expect(dto.reason, isNull);
      expect(dto.appointmentTime, isNull);
      final domain = dto.toDomain();
      expect(domain.reason, isNull);
      expect(domain.appointmentTime, isNull);
    });

    // #5029 : motif du RDV pour anticiper l'acte (ex. "Pose de couronne").
    test('fromJson mappe appointmentReason depuis motif', () {
      final dto = WaitingRoomEntryDto.fromJson({
        'appointment_id': 'd4077170-b80c-4e6b-989e-a1c9877d4617',
        'patient_name_initials': 'MD',
        'checkin_at': '2026-07-13T22:48:48.220795+00:00',
        'wait_minutes': 26,
        'status': 'checked_in',
        'motif': 'Pose de couronne',
      });
      expect(dto.appointmentReason, 'Pose de couronne');
      final domain = dto.toDomain();
      expect(domain.appointmentReason, 'Pose de couronne');
    });

    test('fromJson retombe sur appointment_reason si motif absent', () {
      final dto = WaitingRoomEntryDto.fromJson({
        'appointment_id': 'd4077170-b80c-4e6b-989e-a1c9877d4617',
        'patient_name_initials': 'MD',
        'checkin_at': '2026-07-13T22:48:48.220795+00:00',
        'wait_minutes': 26,
        'status': 'checked_in',
        'appointment_reason': 'Contrôle annuel',
      });
      expect(dto.appointmentReason, 'Contrôle annuel');
      final domain = dto.toDomain();
      expect(domain.appointmentReason, 'Contrôle annuel');
    });

    test('fromJson tolère appointmentReason absent (pas de crash)', () {
      final dto = WaitingRoomEntryDto.fromJson({
        'appointment_id': 'd4077170-b80c-4e6b-989e-a1c9877d4617',
        'patient_name_initials': 'MD',
        'checkin_at': '2026-07-13T22:48:48.220795+00:00',
        'wait_minutes': 26,
        'status': 'checked_in',
      });
      expect(dto.appointmentReason, isNull);
      expect(dto.toDomain().appointmentReason, isNull);
    });

    // #5031 : heure prévue du RDV (pour calculer le retard sur le planning).
    test('fromJson mappe scheduled_at quand présent', () {
      final dto = WaitingRoomEntryDto.fromJson({
        'appointment_id': 'd4077170-b80c-4e6b-989e-a1c9877d4617',
        'patient_name_initials': 'MD',
        'checkin_at': '2026-07-13T22:48:48.220795+00:00',
        'wait_minutes': 26,
        'status': 'checked_in',
        'scheduled_at': '2026-07-13T10:00:00+00:00',
      });
      expect(dto.scheduledAt, '2026-07-13T10:00:00+00:00');
      final domain = dto.toDomain();
      expect(domain.scheduledAt, DateTime.parse('2026-07-13T10:00:00+00:00'));
    });

    test('fromJson tolère scheduled_at absent ou invalide (pas de crash)', () {
      final dto = WaitingRoomEntryDto.fromJson({
        'appointment_id': 'd4077170-b80c-4e6b-989e-a1c9877d4617',
        'patient_name_initials': 'MD',
        'checkin_at': '2026-07-13T22:48:48.220795+00:00',
        'wait_minutes': 26,
        'status': 'checked_in',
      });
      expect(dto.scheduledAt, isNull);
      expect(dto.toDomain().scheduledAt, isNull);

      final invalidDto = WaitingRoomEntryDto.fromJson({
        'appointment_id': 'd4077170-b80c-4e6b-989e-a1c9877d4617',
        'patient_name_initials': 'MD',
        'checkin_at': '2026-07-13T22:48:48.220795+00:00',
        'wait_minutes': 26,
        'status': 'checked_in',
        'scheduled_at': 'not-a-date',
      });
      expect(invalidDto.toDomain().scheduledAt, isNull);
    });

    // #5168 : colonne Praticien salle d'attente — même practitioner_id/nom
    // que l'agenda.
    test('fromJson mappe practitioner_id/practitioner_name quand présents',
        () {
      final dto = WaitingRoomEntryDto.fromJson({
        'appointment_id': 'd4077170-b80c-4e6b-989e-a1c9877d4617',
        'patient_name_initials': 'MD',
        'checkin_at': '2026-07-13T22:48:48.220795+00:00',
        'wait_minutes': 26,
        'status': 'checked_in',
        'practitioner_id': 'pr-1',
        'practitioner_name': 'Dr A. Rousseau',
      });
      expect(dto.practitionerId, 'pr-1');
      expect(dto.practitionerName, 'Dr A. Rousseau');
      final domain = dto.toDomain();
      expect(domain.practitionerId, 'pr-1');
      expect(domain.practitionerName, 'Dr A. Rousseau');
    });

    test('fromJson tolère practitioner_id/practitioner_name absents', () {
      final dto = WaitingRoomEntryDto.fromJson({
        'appointment_id': 'd4077170-b80c-4e6b-989e-a1c9877d4617',
        'patient_name_initials': 'MD',
        'checkin_at': '2026-07-13T22:48:48.220795+00:00',
        'wait_minutes': 26,
        'status': 'checked_in',
      });
      expect(dto.practitionerId, isNull);
      expect(dto.practitionerName, isNull);
      final domain = dto.toDomain();
      expect(domain.practitionerId, isNull);
      expect(domain.practitionerName, isNull);
    });

    // #6636 : `status` n'était jamais parsé — la pastille de la salle
    // d'attente restait figée sur « En attente » pour tout le monde.
    test('fromJson mappe status (checked_in ou in_consultation)', () {
      final checkedIn = WaitingRoomEntryDto.fromJson({
        'appointment_id': 'd4077170-b80c-4e6b-989e-a1c9877d4617',
        'patient_name_initials': 'MD',
        'checkin_at': '2026-07-13T22:48:48.220795+00:00',
        'wait_minutes': 26,
        'status': 'checked_in',
      });
      expect(checkedIn.status, 'checked_in');
      expect(checkedIn.toDomain().status, 'checked_in');

      final inConsultation = WaitingRoomEntryDto.fromJson({
        'appointment_id': 'd4077170-b80c-4e6b-989e-a1c9877d4617',
        'patient_name_initials': 'MD',
        'checkin_at': '2026-07-13T22:48:48.220795+00:00',
        'wait_minutes': 26,
        'status': 'in_consultation',
      });
      expect(inConsultation.status, 'in_consultation');
      expect(inConsultation.toDomain().status, 'in_consultation');
    });

    test('fromJson tolère status absent (pas de crash)', () {
      final dto = WaitingRoomEntryDto.fromJson({
        'appointment_id': 'd4077170-b80c-4e6b-989e-a1c9877d4617',
        'patient_name_initials': 'MD',
        'checkin_at': '2026-07-13T22:48:48.220795+00:00',
        'wait_minutes': 26,
      });
      expect(dto.status, isNull);
      expect(dto.toDomain().status, isNull);
    });
  });
}
