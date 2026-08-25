// Issue #5261 — rail de date (jour abrégé / n° du jour / heure) sur chaque
// carte « à venir » de Mes RDV, à la place de l'avatar d'initiales.
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

  testWidgets(
      'une carte à venir affiche le rail jour/n°/heure au lieu de l\'avatar',
      (tester) async {
    // 2026-08-25 est un mardi ; UTC 12:30 → 14:30 heure de Paris en été
    // (cf. #4620/#4618 : jamais l'heure UTC brute).
    final appt = Appointment(
      id: 'rdv-1',
      cabinetId: 'cab-1',
      practitionerName: 'Dr Lemaire',
      practitionerSpecialty: 'Dentiste',
      startsAt: DateTime.utc(2026, 8, 25, 12, 30),
      duration: const Duration(minutes: 30),
      motif: 'Détartrage',
      status: AppointmentStatus.confirmed,
    );
    final expectedLocal = appt.startsAt.toLocal();
    final expectedHour = expectedLocal.hour.toString().padLeft(2, '0');
    final expectedMinute = expectedLocal.minute.toString().padLeft(2, '0');

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

    expect(find.text('MAR'), findsOneWidget);
    expect(find.text('25'), findsOneWidget);
    expect(find.text('$expectedHour:$expectedMinute'), findsOneWidget);
    expect(find.byType(NubiaAvatar), findsNothing);
  });

  testWidgets('le numéro du jour est zero-paddé sur 2 chiffres',
      (tester) async {
    final appt = Appointment(
      id: 'rdv-2',
      cabinetId: 'cab-1',
      practitionerName: 'Dr Lemaire',
      practitionerSpecialty: 'Dentiste',
      startsAt: DateTime.utc(2026, 9, 2, 8, 0),
      duration: const Duration(minutes: 30),
      motif: 'Contrôle',
      status: AppointmentStatus.confirmed,
    );

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

    expect(find.text('02'), findsOneWidget);
    expect(find.text('2'), findsNothing);
  });
}
