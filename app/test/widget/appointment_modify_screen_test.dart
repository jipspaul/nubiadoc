import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/presentation/features/appointments/bloc/appointment_modify_bloc.dart';
import 'package:nubia_patient/presentation/features/appointments/bloc/booking_bloc.dart';
import 'package:nubia_patient/presentation/features/appointments/pages/appointment_modify_screen.dart';
import 'package:nubia_patient/presentation/features/appointments/widgets/slot_grid.dart';

class MockAppointmentModifyBloc
    extends MockBloc<AppointmentModifyEvent, AppointmentModifyState>
    implements AppointmentModifyBloc {}

Appointment _makeAppointment() => Appointment(
      id: 'appt-1',
      cabinetId: 'cab-1',
      practitionerName: 'Dr. Marin',
      practitionerSpecialty: 'Dentiste',
      startsAt: DateTime.now().add(const Duration(days: 3)),
      duration: const Duration(minutes: 30),
      motif: 'Contrôle',
      status: AppointmentStatus.confirmed,
    );

List<AppointmentSlot> _slots() => List.generate(
      5,
      (i) => AppointmentSlot(
        id: 'slot-$i',
        startsAt: DateTime.now().add(Duration(days: i + 1)),
        duration: const Duration(minutes: 30),
        available: true,
      ),
    );

Widget _wrapModify(AppointmentModifyBloc bloc, Appointment appointment) {
  return MaterialApp(
    home: BlocProvider<AppointmentModifyBloc>.value(
      value: bloc,
      child: AppointmentModifyScreen(appointment: appointment),
    ),
  );
}

void main() {
  late MockAppointmentModifyBloc bloc;
  late Appointment appointment;

  setUp(() {
    bloc = MockAppointmentModifyBloc();
    appointment = _makeAppointment();
  });

  tearDown(() => bloc.close());

  testWidgets(
    'AppointmentModifyScreen affiche un loader en état Initial',
    (tester) async {
      when(() => bloc.state).thenReturn(const AppointmentModifyInitial());

      await tester.pumpWidget(_wrapModify(bloc, appointment));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  testWidgets(
    'AppointmentModifyScreen affiche les créneaux et le RDV actuel en état Ready',
    (tester) async {
      when(() => bloc.state).thenReturn(
        AppointmentModifyReady(
          original: appointment,
          slots: _slots(),
        ),
      );

      await tester.pumpWidget(_wrapModify(bloc, appointment));

      // Current appointment info card is rendered.
      expect(find.text('Rendez-vous actuel'), findsOneWidget);
      // Slot grid is rendered.
      expect(find.byType(SlotGrid), findsOneWidget);
      // Confirm button is present.
      expect(find.text('Confirmer le déplacement'), findsOneWidget);
    },
  );
}
