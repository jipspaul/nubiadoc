// Issue #6193 — l'onglet « Historique » de « Mes RDV » n'affichait jamais
// les RDV passés : le SegmentedControl basculait seulement l'IndexedStack
// local sans jamais dispatcher `MesRdvHistoryRequested`, laissant
// `_onHistoryLoad` (mes_rdv_bloc.dart) inatteint et l'historique figé vide.
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

  Appointment appt(String id, DateTime startsAt) => Appointment(
        id: id,
        cabinetId: 'cab-1',
        practitionerName: 'Dr Lemaire',
        practitionerSpecialty: 'Dentiste',
        startsAt: startsAt,
        duration: const Duration(minutes: 30),
        motif: 'Contrôle',
        status: AppointmentStatus.confirmed,
      );

  testWidgets('tap "Historique" dispatche MesRdvHistoryRequested',
      (tester) async {
    final state = MesRdvLoaded(
      upcoming: [appt('rdv-1', DateTime.now().add(const Duration(days: 2)))],
      history: const [],
    );
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

    await tester.tap(find.text('Historique'));
    await tester.pumpAndSettle();

    verify(
      () => mockBloc.add(any(that: isA<MesRdvHistoryRequested>())),
    ).called(1);
  });

  testWidgets('tap "Historique" puis "À venir" ne redispatche pas',
      (tester) async {
    final state = MesRdvLoaded(
      upcoming: [appt('rdv-1', DateTime.now().add(const Duration(days: 2)))],
      history: const [],
    );
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

    await tester.tap(find.text('Historique'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('À venir'));
    await tester.pumpAndSettle();

    verify(
      () => mockBloc.add(any(that: isA<MesRdvHistoryRequested>())),
    ).called(1);
  });
}
