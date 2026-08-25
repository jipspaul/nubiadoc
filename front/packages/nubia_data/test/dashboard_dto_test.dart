import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/nubia_data.dart';

void main() {
  group('DashboardDto.fromJson', () {
    // #5197 : la carte héros de l'accueil patient a besoin des détails du
    // prochain RDV (date/heure, praticien, motif, adresse), pas seulement
    // du compteur 0/1 `upcomingAppointments`.
    test('avec next_appointment → mappe les détails et upcomingAppointments=1',
        () {
      final dto = DashboardDto.fromJson({
        'next_appointment': {
          'appointment_id': 'appt-1',
          'starts_at': '2026-08-13T14:30:00Z',
          'status': 'confirmed',
          'practitioner_name': 'Dr Amélie Rousseau',
          'reason': 'Détartrage',
          'address_lines': [
            'Cabinet Nubia Opéra — 12 rue de la Paix, 75002 Paris',
            '2e étage, ascenseur',
          ],
        },
        'to_sign': [],
        'to_pay': [],
        'unread_messages': 0,
      });
      final summary = dto.toDomain();

      expect(summary.upcomingAppointments, 1);
      expect(summary.nextAppointment, isNotNull);
      expect(summary.nextAppointment!.appointmentId, 'appt-1');
      expect(
        summary.nextAppointment!.startsAt,
        DateTime.parse('2026-08-13T14:30:00Z'),
      );
      expect(
        summary.nextAppointment!.practitionerName,
        'Dr Amélie Rousseau',
      );
      expect(summary.nextAppointment!.reason, 'Détartrage');
      expect(summary.nextAppointment!.addressLines, [
        'Cabinet Nubia Opéra — 12 rue de la Paix, 75002 Paris',
        '2e étage, ascenseur',
      ]);
    });

    test(
        'sans next_appointment → nextAppointment null et upcomingAppointments=0',
        () {
      final dto = DashboardDto.fromJson({
        'to_sign': [],
        'to_pay': [],
        'unread_messages': 0,
      });
      final summary = dto.toDomain();

      expect(summary.upcomingAppointments, 0);
      expect(summary.nextAppointment, isNull);
    });

    test(
        'next_appointment sans sous-clés optionnelles → nullable, pas de crash',
        () {
      final dto = DashboardDto.fromJson({
        'next_appointment': {
          'appointment_id': 'appt-2',
          'starts_at': '2026-08-13T14:30:00Z',
          'status': 'confirmed',
        },
        'to_sign': [],
        'to_pay': [],
        'unread_messages': 0,
      });
      final summary = dto.toDomain();

      expect(summary.nextAppointment, isNotNull);
      expect(summary.nextAppointment!.practitionerName, isNull);
      expect(summary.nextAppointment!.reason, isNull);
      expect(summary.nextAppointment!.addressLines, isNull);
    });
  });
}
