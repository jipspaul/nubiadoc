// Issue #3352 — sur la vraie carte Mes RDV, le patient cherche d'abord CHEZ
// QUI il a rendez-vous : le praticien doit être le titre, le motif le
// secondaire. Rend la vraie MesRdvPage (bloc via GetIt, comme en prod).
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

  final appt = Appointment(
    id: 'rdv-1',
    cabinetId: 'cab-1',
    practitionerName: 'Dr Lemaire',
    practitionerSpecialty: 'Dentiste',
    startsAt: DateTime.now().add(const Duration(days: 2)),
    duration: const Duration(minutes: 30),
    motif: 'Détartrage',
    status: AppointmentStatus.confirmed,
  );

  late _MockMesRdvBloc mockBloc;

  setUp(() async {
    mockBloc = _MockMesRdvBloc();
    await GetIt.instance.reset();
    GetIt.instance.registerFactory<MesRdvBloc>(() => mockBloc);
  });

  tearDown(() async => GetIt.instance.reset());

  testWidgets('le praticien est le titre de la carte, le motif le secondaire',
      (tester) async {
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

    final practitionerFinder = find.text('Dr Lemaire');
    final motifFinder = find.text('Détartrage · Dentiste');
    expect(practitionerFinder, findsOneWidget);
    expect(motifFinder, findsOneWidget);

    final theme = Theme.of(tester.element(motifFinder));
    final title = tester.widget<Text>(practitionerFinder);
    final subtitle = tester.widget<Text>(motifFinder);
    expect(
      title.style?.fontSize,
      theme.textTheme.titleSmall?.fontSize,
      reason: 'le praticien doit porter le style de titre',
    );
    expect(
      subtitle.style?.fontSize,
      theme.textTheme.bodySmall?.fontSize,
      reason: 'le motif doit être secondaire',
    );
  });
}
