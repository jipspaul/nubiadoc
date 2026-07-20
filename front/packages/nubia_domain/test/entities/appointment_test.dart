// Régression #3804 — canCancel/canModify ne couvraient que le statut
// `confirmed`, alors que le back autorise l'annulation d'un RDV `requested`
// (la classe majoritaire des RDV patient) et `checkedIn`. Un patient ne
// pouvait retirer aucune demande en attente depuis l'app.
import 'package:nubia_domain/nubia_domain.dart';
import 'package:test/test.dart';

Appointment _appt({
  required AppointmentStatus status,
  required DateTime startsAt,
}) =>
    Appointment(
      id: 'appt-1',
      cabinetId: 'cab-1',
      practitionerName: 'Dr Test',
      practitionerSpecialty: 'Dentiste',
      startsAt: startsAt,
      duration: const Duration(minutes: 30),
      motif: 'Contrôle',
      status: status,
    );

void main() {
  group('Appointment.canCancel', () {
    test('requested dans plus de 2h -> true (#3804)', () {
      final appt = _appt(
        status: AppointmentStatus.requested,
        startsAt: DateTime.now().add(const Duration(days: 3)),
      );
      expect(appt.canCancel, isTrue);
    });

    test('confirmed dans plus de 2h -> true', () {
      final appt = _appt(
        status: AppointmentStatus.confirmed,
        startsAt: DateTime.now().add(const Duration(days: 3)),
      );
      expect(appt.canCancel, isTrue);
    });

    test('requested à moins de 2h -> false (fenêtre back)', () {
      final appt = _appt(
        status: AppointmentStatus.requested,
        startsAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(appt.canCancel, isFalse);
    });

    test('checkedIn à moins de 2h -> true (sortie de file toujours possible)',
        () {
      final appt = _appt(
        status: AppointmentStatus.checkedIn,
        startsAt: DateTime.now().add(const Duration(minutes: 30)),
      );
      expect(appt.canCancel, isTrue);
    });

    test('cancelled -> false', () {
      final appt = _appt(
        status: AppointmentStatus.cancelled,
        startsAt: DateTime.now().add(const Duration(days: 3)),
      );
      expect(appt.canCancel, isFalse);
    });

    test('completed -> false', () {
      final appt = _appt(
        status: AppointmentStatus.completed,
        startsAt: DateTime.now().subtract(const Duration(days: 3)),
      );
      expect(appt.canCancel, isFalse);
    });

    test('inProgress -> false (consultation en cours)', () {
      final appt = _appt(
        status: AppointmentStatus.inProgress,
        startsAt: DateTime.now().subtract(const Duration(minutes: 10)),
      );
      expect(appt.canCancel, isFalse);
    });

    test('requested déjà passé (starts_at dans le passé) -> true (#3811)', () {
      final appt = _appt(
        status: AppointmentStatus.requested,
        startsAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(appt.canCancel, isTrue);
    });
  });

  group('Appointment.canModify', () {
    test('requested dans plus de 24h -> true', () {
      final appt = _appt(
        status: AppointmentStatus.requested,
        startsAt: DateTime.now().add(const Duration(days: 3)),
      );
      expect(appt.canModify, isTrue);
    });

    test('requested à moins de 24h -> false', () {
      final appt = _appt(
        status: AppointmentStatus.requested,
        startsAt: DateTime.now().add(const Duration(hours: 10)),
      );
      expect(appt.canModify, isFalse);
    });

    test('checkedIn -> false (pas de reprogrammation, back n\'accepte pas)',
        () {
      final appt = _appt(
        status: AppointmentStatus.checkedIn,
        startsAt: DateTime.now().add(const Duration(days: 3)),
      );
      expect(appt.canModify, isFalse);
    });
  });
}
