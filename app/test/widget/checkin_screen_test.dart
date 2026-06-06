import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/presentation/features/appointments/bloc/checkin_bloc.dart';
import 'package:nubia_patient/presentation/features/appointments/pages/checkin_screen.dart';
import 'package:nubia_patient/presentation/theme/nubia_theme.dart';

class MockCheckinBloc extends MockBloc<CheckinEvent, CheckinState>
    implements CheckinBloc {}

Appointment _makeAppointment() => Appointment(
      id: 'appt-1',
      cabinetId: 'cab-1',
      practitionerName: 'Dr. Leroy',
      practitionerSpecialty: 'Dentiste',
      startsAt: DateTime.now().add(const Duration(hours: 2)),
      duration: const Duration(minutes: 30),
      motif: 'Détartrage',
      status: AppointmentStatus.confirmed,
      cabinetAddress: '12 rue de la Paix, Paris',
    );

Widget _wrap(CheckinBloc bloc, Appointment appointment) {
  return MaterialApp(
    theme: NubiaTheme.light,
    home: BlocProvider<CheckinBloc>.value(
      value: bloc,
      child: CheckinScreen(appointment: appointment),
    ),
  );
}

void main() {
  late MockCheckinBloc bloc;
  late Appointment appointment;

  setUpAll(() async {
    await initializeDateFormatting('fr');
  });

  setUp(() {
    bloc = MockCheckinBloc();
    appointment = _makeAppointment();
  });

  tearDown(() => bloc.close());

  testWidgets('CheckinScreen s\'affiche sans erreur en état Initial',
      (tester) async {
    when(() => bloc.state).thenReturn(const CheckinInitial());

    await tester.pumpWidget(_wrap(bloc, appointment));

    expect(find.byType(CheckinScreen), findsOneWidget);
    expect(find.text('Je suis arrivé(e)'), findsOneWidget);
  });

  testWidgets('CheckinScreen affiche le motif du RDV', (tester) async {
    when(() => bloc.state).thenReturn(const CheckinInitial());

    await tester.pumpWidget(_wrap(bloc, appointment));

    expect(find.text('Détartrage'), findsOneWidget);
  });

  testWidgets('CheckinScreen affiche le nom du praticien', (tester) async {
    when(() => bloc.state).thenReturn(const CheckinInitial());

    await tester.pumpWidget(_wrap(bloc, appointment));

    expect(find.textContaining('Dr. Leroy'), findsOneWidget);
  });

  testWidgets('CheckinScreen affiche un loader en état InProgress',
      (tester) async {
    when(() => bloc.state).thenReturn(const CheckinInProgress());

    await tester.pumpWidget(_wrap(bloc, appointment));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Button is disabled while in progress.
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('CheckinScreen envoie CheckinRequested au tap du bouton',
      (tester) async {
    when(() => bloc.state).thenReturn(const CheckinInitial());

    await tester.pumpWidget(_wrap(bloc, appointment));
    await tester.tap(find.text('Je suis arrivé(e)'));
    await tester.pump();

    verify(
      () => bloc.add(const CheckinRequested('appt-1')),
    ).called(1);
  });
}
