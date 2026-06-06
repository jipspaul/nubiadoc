import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/domain/usecases/appointments/get_appointment_by_id_use_case.dart';
import 'package:nubia_patient/presentation/features/appointments/bloc/checkin_bloc.dart';
import 'package:nubia_patient/presentation/features/appointments/pages/appointment_detail_screen.dart';
import 'package:nubia_patient/presentation/theme/nubia_theme.dart';

class MockGetAppointmentByIdUseCase extends Mock
    implements GetAppointmentByIdUseCase {}

class MockCheckinBloc extends MockBloc<CheckinEvent, CheckinState>
    implements CheckinBloc {}

Appointment _makeAppointment() => Appointment(
      id: 'appt-42',
      cabinetId: 'cab-1',
      practitionerName: 'Dr. Dumont',
      practitionerSpecialty: 'Chirurgien-dentiste',
      startsAt: DateTime.now().add(const Duration(days: 3)),
      duration: const Duration(minutes: 45),
      motif: 'Contrôle annuel',
      status: AppointmentStatus.confirmed,
      cabinetAddress: '5 avenue Victor Hugo, Lyon',
    );

void main() {
  late MockGetAppointmentByIdUseCase mockGetById;
  late MockCheckinBloc mockCheckinBloc;
  late Appointment appointment;

  setUpAll(() async {
    await initializeDateFormatting('fr');
    registerFallbackValue('');
  });

  setUp(() {
    mockGetById = MockGetAppointmentByIdUseCase();
    mockCheckinBloc = MockCheckinBloc();
    appointment = _makeAppointment();
  });

  tearDown(() async {
    await mockCheckinBloc.close();
  });

  Widget wrap(String id) {
    return MaterialApp(
      theme: NubiaTheme.light,
      home: AppointmentDetailScreen(
        id: id,
        checkinBloc: mockCheckinBloc,
        getAppointmentByIdUseCase: mockGetById,
      ),
    );
  }

  testWidgets(
    'AppointmentDetailScreen affiche un loader pendant le chargement',
    (tester) async {
      // Use a Completer that never completes to keep the widget in loading
      // state without leaving a pending timer that would fail the test.
      final completer = Completer<Either<Failure, Appointment>>();
      when(() => mockCheckinBloc.state).thenReturn(const CheckinInitial());
      when(() => mockGetById(any())).thenAnswer((_) => completer.future);

      await tester.pumpWidget(wrap('appt-42'));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete the future to avoid "Completer was never completed" warnings.
      completer.complete(Right(appointment));
      await tester.pump();
    },
  );

  testWidgets(
    'AppointmentDetailScreen affiche le détail du RDV après chargement',
    (tester) async {
      when(() => mockCheckinBloc.state).thenReturn(const CheckinInitial());
      when(() => mockGetById(any()))
          .thenAnswer((_) async => Right(appointment));

      await tester.pumpWidget(wrap('appt-42'));
      await tester.pump();

      expect(find.text('Contrôle annuel'), findsOneWidget);
      expect(find.textContaining('Dr. Dumont'), findsOneWidget);
    },
  );

  testWidgets(
    'AppointmentDetailScreen affiche le bouton check-in pour un RDV confirmé',
    (tester) async {
      when(() => mockCheckinBloc.state).thenReturn(const CheckinInitial());
      when(() => mockGetById(any()))
          .thenAnswer((_) async => Right(appointment));

      await tester.pumpWidget(wrap('appt-42'));
      await tester.pump();

      expect(find.text('Effectuer le check-in'), findsOneWidget);
    },
  );

  testWidgets(
    'AppointmentDetailScreen affiche une erreur en cas d\'échec',
    (tester) async {
      when(() => mockCheckinBloc.state).thenReturn(const CheckinInitial());
      when(() => mockGetById(any())).thenAnswer(
        (_) async => const Left(NotFoundFailure('RDV introuvable.')),
      );

      await tester.pumpWidget(wrap('appt-err'));
      await tester.pump();

      expect(find.text('RDV introuvable.'), findsOneWidget);
    },
  );
}
