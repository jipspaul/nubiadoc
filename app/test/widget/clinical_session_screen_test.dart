import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/domain/entities/clinical_session.dart';
import 'package:nubia_patient/presentation/features/clinical/bloc/clinical_session_bloc.dart';
import 'package:nubia_patient/presentation/features/clinical/pages/clinical_session_screen.dart';
import 'package:nubia_patient/presentation/theme/nubia_theme.dart';

class MockClinicalSessionBloc
    extends MockBloc<ClinicalSessionEvent, ClinicalSessionState>
    implements ClinicalSessionBloc {}

Appointment _makeAppointment() => Appointment(
      id: 'appt-1',
      cabinetId: 'cab-1',
      practitionerName: 'Dr. Martin',
      practitionerSpecialty: 'Dentiste',
      startsAt: DateTime.now().add(const Duration(hours: 1)),
      duration: const Duration(minutes: 30),
      motif: 'Extraction',
      status: AppointmentStatus.confirmed,
    );

ClinicalSession _makeSession({List<ClinicalAct> acts = const []}) =>
    ClinicalSession(
      id: 'consult-1',
      appointmentId: 'appt-1',
      status: 'in_progress',
      acts: acts,
    );

Widget _wrap(ClinicalSessionBloc bloc, Appointment appointment) {
  return MaterialApp(
    theme: NubiaTheme.light,
    home: BlocProvider<ClinicalSessionBloc>.value(
      value: bloc,
      child: ClinicalSessionScreen(appointment: appointment),
    ),
  );
}

void main() {
  late MockClinicalSessionBloc bloc;
  late Appointment appointment;

  setUp(() {
    bloc = MockClinicalSessionBloc();
    appointment = _makeAppointment();
  });

  tearDown(() => bloc.close());

  // -------------------------------------------------------------------------
  // Initial state
  // -------------------------------------------------------------------------

  testWidgets(
    'ClinicalSessionScreen affiche le bouton Démarrer en état Initial',
    (tester) async {
      when(() => bloc.state).thenReturn(const ClinicalSessionInitial());

      await tester.pumpWidget(_wrap(bloc, appointment));

      expect(find.text('Démarrer la consultation'), findsOneWidget);
    },
  );

  testWidgets(
    'ClinicalSessionScreen affiche le motif du RDV en état Initial',
    (tester) async {
      when(() => bloc.state).thenReturn(const ClinicalSessionInitial());

      await tester.pumpWidget(_wrap(bloc, appointment));

      expect(find.text('Extraction'), findsOneWidget);
    },
  );

  testWidgets(
    'Tap sur Démarrer envoie SessionStartRequested',
    (tester) async {
      when(() => bloc.state).thenReturn(const ClinicalSessionInitial());

      await tester.pumpWidget(_wrap(bloc, appointment));
      await tester.tap(find.text('Démarrer la consultation'));
      await tester.pump();

      verify(() => bloc.add(const SessionStartRequested('appt-1'))).called(1);
    },
  );

  // -------------------------------------------------------------------------
  // Loading state
  // -------------------------------------------------------------------------

  testWidgets(
    'ClinicalSessionScreen affiche un loader en état Loading',
    (tester) async {
      when(() => bloc.state).thenReturn(const ClinicalSessionLoading());

      await tester.pumpWidget(_wrap(bloc, appointment));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  // -------------------------------------------------------------------------
  // Loaded state — session active
  // -------------------------------------------------------------------------

  testWidgets(
    'ClinicalSessionScreen affiche le formulaire d\'acte en état Loaded',
    (tester) async {
      when(() => bloc.state).thenReturn(
        ClinicalSessionLoaded(session: _makeSession()),
      );

      await tester.pumpWidget(_wrap(bloc, appointment));

      expect(find.text('Ajouter un acte CCAM'), findsOneWidget);
      expect(find.text('Terminer & facturer'), findsOneWidget);
    },
  );

  testWidgets(
    'ClinicalSessionScreen affiche les actes existants',
    (tester) async {
      final session = _makeSession(acts: [
        const ClinicalAct(
          id: 'act-1',
          ccamCode: 'HBMD046',
          label: 'Extraction dent de sagesse',
          tooth: '38',
          amountCents: 12000,
        ),
      ]);
      when(() => bloc.state)
          .thenReturn(ClinicalSessionLoaded(session: session));

      await tester.pumpWidget(_wrap(bloc, appointment));

      expect(find.text('Extraction dent de sagesse'), findsOneWidget);
      expect(find.text('HBMD046 · dent 38'), findsOneWidget);
      expect(find.text('120.00 €'), findsOneWidget);
    },
  );

  testWidgets(
    'Tap Terminer & facturer envoie SessionCompleteRequested',
    (tester) async {
      when(() => bloc.state).thenReturn(
        ClinicalSessionLoaded(session: _makeSession()),
      );

      await tester.pumpWidget(_wrap(bloc, appointment));
      await tester.tap(find.text('Terminer & facturer'));
      await tester.pump();

      verify(
        () => bloc.add(const SessionCompleteRequested('consult-1')),
      ).called(1);
    },
  );

  // -------------------------------------------------------------------------
  // Error state
  // -------------------------------------------------------------------------

  testWidgets(
    'ClinicalSessionScreen affiche le message d\'erreur',
    (tester) async {
      when(() => bloc.state)
          .thenReturn(const ClinicalSessionError('Erreur réseau'));

      await tester.pumpWidget(_wrap(bloc, appointment));

      expect(find.text('Erreur réseau'), findsOneWidget);
    },
  );
}
