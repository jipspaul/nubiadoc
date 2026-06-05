import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';

void main() {
  group('Appointment', () {
    test('isUpcoming returns true for confirmed future appointment', () {
      final appt = Appointment(
        id: '1',
        cabinetId: 'cab1',
        practitionerName: 'Dr. Test',
        practitionerSpecialty: 'Dentiste',
        startsAt: DateTime.now().add(const Duration(days: 2)),
        duration: const Duration(minutes: 30),
        motif: 'Contrôle',
        status: AppointmentStatus.confirmed,
      );
      expect(appt.isUpcoming, isTrue);
      expect(appt.canCancel, isTrue);
    });

    test('isUpcoming returns false for past appointment', () {
      final appt = Appointment(
        id: '2',
        cabinetId: 'cab1',
        practitionerName: 'Dr. Test',
        practitionerSpecialty: 'Dentiste',
        startsAt: DateTime.now().subtract(const Duration(days: 1)),
        duration: const Duration(minutes: 30),
        motif: 'Contrôle',
        status: AppointmentStatus.completed,
      );
      expect(appt.isUpcoming, isFalse);
    });
  });
}
