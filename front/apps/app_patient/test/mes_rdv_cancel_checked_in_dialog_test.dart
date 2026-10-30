// Issue #8481 — un RDV `checked_in` annulé est enregistré comme une
// absence (no_show) côté serveur (api/src/appointments_actions.rs) ; le
// dialogue de confirmation du menu « ⋯ » (mes_rdv_page.dart) doit
// l'annoncer avant de confirmer, pas seulement dire que l'action est
// irréversible.
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

  Appointment appointment(AppointmentStatus status) => Appointment(
        id: 'rdv-1',
        cabinetId: 'cab-1',
        practitionerName: 'Dr Lemaire',
        practitionerSpecialty: 'Dentiste',
        // #3804 : `canCancel` bloque un `confirmed` moins de 2h avant le
        // RDV — on reste loin de cette fenêtre pour isoler l'assertion sur
        // le texte du dialogue (hors scope de ce test).
        startsAt: DateTime.now().add(const Duration(hours: 5)),
        duration: const Duration(minutes: 30),
        motif: 'Détartrage',
        status: status,
      );

  Future<void> openCancelDialog(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('more_actions_rdv-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel_rdv-1')));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'RDV checked_in : le dialogue annonce une absence (no-show) au dossier',
      (tester) async {
    await pump(tester, appointment(AppointmentStatus.checkedIn));

    await openCancelDialog(tester);

    expect(find.textContaining('absence (no-show)'), findsOneWidget);
    expect(find.text('Cette action est irréversible.'), findsNothing);
  });

  testWidgets('RDV confirmed : le dialogue ne mentionne pas d\'absence',
      (tester) async {
    await pump(tester, appointment(AppointmentStatus.confirmed));

    await openCancelDialog(tester);

    expect(find.textContaining('absence'), findsNothing);
    expect(find.text('Cette action est irréversible.'), findsOneWidget);
  });
}
