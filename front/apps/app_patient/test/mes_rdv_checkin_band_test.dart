// Issue #5265 — maquette design-v2 point #3 : le check-in sort du `Wrap`
// d'actions pour devenir un bandeau pleine largeur.
// Issue #6447 : le bandeau ne doit s'afficher que quand le check-in peut
// réellement réussir côté back (`checkin_appointment`,
// api/src/appointments_checkin.rs) — status = 'confirmed' ET starts_at
// dans la fenêtre ± 60 min — et non plus sur toute la journée calendaire
// quel que soit le statut.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/mes_rdv/mes_rdv_bloc.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_event.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_page.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_state.dart';

class _MockMesRdvBloc extends MockBloc<MesRdvEvent, MesRdvState>
    implements MesRdvBloc {}

void main() {
  setUpAll(() {
    registerFallbackValue(const MesRdvLoadRequested());
  });

  late _MockMesRdvBloc mockBloc;

  setUp(() async {
    mockBloc = _MockMesRdvBloc();
    await GetIt.instance.reset();
    GetIt.instance.registerFactory<MesRdvBloc>(() => mockBloc);
  });

  tearDown(() async => GetIt.instance.reset());

  Future<void> pump(WidgetTester tester, Appointment appt) async {
    final state = MesRdvLoaded(upcoming: [appt], history: const []);
    whenListen(
      mockBloc,
      Stream<MesRdvState>.fromIterable([state]).asBroadcastStream(),
      initialState: state,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: MesRdvPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  String hhmm(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Appointment appointment({
    required DateTime startsAt,
    AppointmentStatus status = AppointmentStatus.confirmed,
  }) =>
      Appointment(
        id: 'rdv-1',
        cabinetId: 'cab-1',
        practitionerName: 'Dr Lemaire',
        practitionerSpecialty: 'Dentiste',
        startsAt: startsAt,
        duration: const Duration(minutes: 30),
        motif: 'Détartrage',
        status: status,
      );

  testWidgets(
      'un RDV confirmé dans la fenêtre des 60 min affiche le bandeau check-in',
      (tester) async {
    final startsAt = DateTime.now().add(const Duration(minutes: 20));
    await pump(tester, appointment(startsAt: startsAt));

    expect(
      find.text(
        'Vous êtes attendu à ${hhmm(startsAt)} — signalez votre arrivée',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.how_to_reg), findsOneWidget);
    expect(find.text('Je suis là'), findsOneWidget);
    expect(find.byKey(const Key('checkin_rdv-1')), findsOneWidget);
  });

  testWidgets('un RDV confirmé à J+3 n\'affiche aucun check-in', (tester) async {
    await pump(
      tester,
      appointment(startsAt: DateTime.now().add(const Duration(days: 3))),
    );

    expect(find.text('Je suis là'), findsNothing);
    expect(find.byKey(const Key('checkin_rdv-1')), findsNothing);
    expect(find.byIcon(Icons.how_to_reg), findsNothing);
  });

  testWidgets(
      'un RDV confirmé aujourd\'hui mais hors fenêtre ± 60 min n\'affiche aucun check-in',
      (tester) async {
    await pump(
      tester,
      appointment(startsAt: DateTime.now().add(const Duration(hours: 3))),
    );

    expect(find.text('Je suis là'), findsNothing);
    expect(find.byKey(const Key('checkin_rdv-1')), findsNothing);
    expect(find.byIcon(Icons.how_to_reg), findsNothing);
  });

  testWidgets('le bandeau disparaît dès que le statut passe à checkedIn',
      (tester) async {
    await pump(
      tester,
      appointment(
        startsAt: DateTime.now().add(const Duration(minutes: 20)),
        status: AppointmentStatus.checkedIn,
      ),
    );

    expect(find.text('Je suis là'), findsNothing);
    expect(find.byKey(const Key('checkin_rdv-1')), findsNothing);
  });

  testWidgets(
      'un RDV annulé dans la fenêtre du jour n\'affiche jamais le check-in (#6447)',
      (tester) async {
    await pump(
      tester,
      appointment(
        startsAt: DateTime.now().add(const Duration(minutes: 20)),
        status: AppointmentStatus.cancelled,
      ),
    );

    expect(find.text('Je suis là'), findsNothing);
    expect(find.byKey(const Key('checkin_rdv-1')), findsNothing);
    expect(find.byIcon(Icons.how_to_reg), findsNothing);
  });

  testWidgets(
      'un RDV non confirmé (requested) dans la fenêtre du jour n\'affiche jamais le check-in (#6447)',
      (tester) async {
    await pump(
      tester,
      appointment(
        startsAt: DateTime.now().add(const Duration(minutes: 20)),
        status: AppointmentStatus.requested,
      ),
    );

    expect(find.text('Je suis là'), findsNothing);
    expect(find.byKey(const Key('checkin_rdv-1')), findsNothing);
    expect(find.byIcon(Icons.how_to_reg), findsNothing);
  });

  testWidgets('tap "Je suis là" dispatche MesRdvCheckinRequested',
      (tester) async {
    await pump(
      tester,
      appointment(startsAt: DateTime.now().add(const Duration(minutes: 20))),
    );

    await tester.tap(find.byKey(const Key('checkin_rdv-1')));
    await tester.pumpAndSettle();

    verify(
      () => mockBloc.add(
        any(
          that: isA<MesRdvCheckinRequested>()
              .having((e) => e.appointmentId, 'appointmentId', 'rdv-1'),
        ),
      ),
    ).called(1);
  });
}
