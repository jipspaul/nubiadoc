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
  });
}
