// #4664 : `GET /cabinet/appointments` n'émet jamais `practitioner_name`
// (seulement `practitioner_id`) — le nom doit être résolu côté client via le
// roster des praticiens du cabinet (`CabinetAgendaRepository.
// listPractitioners`), `''` uniquement si le practitioner_id est inconnu.
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_data/src/remote/cabinet_appointments/cabinet_appointments_api.dart';
import 'package:nubia_data/src/remote/cabinet_appointments/cabinet_appointments_dto.dart';
import 'package:nubia_data/src/repositories/cabinet_appointments_repository_impl.dart';
import 'package:nubia_domain/src/entities/cabinet_practitioner.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_agenda_repository.dart';

class MockCabinetAppointmentsApi extends Mock
    implements CabinetAppointmentsApi {}

class MockCabinetAgendaRepository extends Mock
    implements CabinetAgendaRepository {}

void main() {
  late MockCabinetAppointmentsApi api;
  late MockCabinetAgendaRepository agendaRepository;
  late CabinetAppointmentsRepositoryImpl repository;

  setUp(() {
    api = MockCabinetAppointmentsApi();
    agendaRepository = MockCabinetAgendaRepository();
    repository = CabinetAppointmentsRepositoryImpl(api, agendaRepository);
  });

  CabinetAppointmentDto dtoFor(String practitionerId) => CabinetAppointmentDto(
        id: 'appt-1',
        cabinetId: 'cabinet-1',
        patientId: 'patient-1',
        patientName: 'Jean Dupont',
        practitionerId: practitionerId,
        // Jamais émis par l'API : simule le JSON réel.
        practitionerName: '',
        startsAt: DateTime(2026, 1, 6, 9).toIso8601String(),
        durationMinutes: 30,
        motif: 'Contrôle',
        status: 'requested',
      );

  test('resout le nom du praticien via le roster quand practitioner_id est connu',
      () async {
    when(() => api.list(page: any(named: 'page')))
        .thenAnswer((_) async => [dtoFor('prat-1')]);
    when(() => agendaRepository.listPractitioners()).thenAnswer(
      (_) async => const Right([
        CabinetPractitioner(id: 'prat-1', displayName: 'Dr Hugo Marin'),
      ]),
    );

    final result = await repository.list();

    result.fold(
      (failure) => fail('devrait être un Right, obtenu $failure'),
      (appointments) {
        expect(appointments, hasLength(1));
        expect(appointments.first.practitionerName, 'Dr Hugo Marin');
      },
    );
  });

  test('renvoie une chaine vide quand practitioner_id est inconnu du roster',
      () async {
    when(() => api.list(page: any(named: 'page')))
        .thenAnswer((_) async => [dtoFor('prat-inconnu')]);
    when(() => agendaRepository.listPractitioners()).thenAnswer(
      (_) async => const Right([
        CabinetPractitioner(id: 'prat-1', displayName: 'Dr Hugo Marin'),
      ]),
    );

    final result = await repository.list();

    result.fold(
      (failure) => fail('devrait être un Right, obtenu $failure'),
      (appointments) {
        expect(appointments, hasLength(1));
        expect(appointments.first.practitionerName, '');
      },
    );
  });
}
