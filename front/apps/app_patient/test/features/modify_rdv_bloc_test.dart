import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/mes_rdv/modify_rdv_bloc.dart';
import 'package:app_patient/features/mes_rdv/modify_rdv_event.dart';
import 'package:app_patient/features/mes_rdv/modify_rdv_state.dart';

class MockGetAppointmentByIdUseCase extends Mock
    implements GetAppointmentByIdUseCase {}

class MockSearchSlotsUseCase extends Mock implements SearchSlotsUseCase {}

class MockModifyAppointmentUseCase extends Mock
    implements ModifyAppointmentUseCase {}

void main() {
  late MockGetAppointmentByIdUseCase getAppointment;
  late MockSearchSlotsUseCase searchSlots;
  late MockModifyAppointmentUseCase modifyAppointment;

  final appointment = Appointment(
    id: 'appt-1',
    cabinetId: 'cab-1',
    practitionerName: 'Dr Test',
    practitionerSpecialty: 'Dentiste',
    startsAt: DateTime.now().add(const Duration(days: 10)),
    duration: const Duration(minutes: 30),
    motif: 'Contrôle',
    status: AppointmentStatus.confirmed,
    type: AppointmentType.inPerson,
    practitionerId: 'prac-1',
  );

  Slot slot(DateTime startsAt) => Slot(
    id: startsAt.toIso8601String(),
    cabinetId: 'cab-1',
    practitionerId: 'prac-1',
    startsAt: startsAt,
    endsAt: startsAt.add(const Duration(minutes: 30)),
    isAvailable: true,
  );

  setUp(() {
    getAppointment = MockGetAppointmentByIdUseCase();
    searchSlots = MockSearchSlotsUseCase();
    modifyAppointment = MockModifyAppointmentUseCase();

    when(() => getAppointment(any()))
        .thenAnswer((_) async => Right(appointment));
  });

  ModifyRdvBloc buildBloc() => ModifyRdvBloc(
    getAppointment: getAppointment,
    searchSlots: searchSlots,
    modifyAppointment: modifyAppointment,
  );

  // #4532 : un créneau à moins de 24h ne doit jamais être proposé comme
  // sélectionnable en reprogrammation — le back le refuse (409 too_late).
  blocTest<ModifyRdvBloc, ModifyRdvState>(
    'créneau à moins de 24h grisé, créneau au-delà disponible',
    build: buildBloc,
    setUp: () {
      when(() => searchSlots(providerId: any(named: 'providerId'))).thenAnswer(
        (_) async => Right([
          slot(DateTime.now().add(const Duration(hours: 2))),
          slot(DateTime.now().add(const Duration(hours: 48))),
        ]),
      );
    },
    act: (bloc) => bloc.add(const ModifyRdvLoadRequested('appt-1')),
    expect: () => [
      isA<ModifyRdvLoading>(),
      isA<ModifyRdvLoaded>().having(
        (s) => s.slots.map((s) => s.isAvailable).toList(),
        'isAvailable per slot',
        [false, true],
      ),
    ],
  );
}
