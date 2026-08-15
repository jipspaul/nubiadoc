//! Test widget : pastille de statut de traçabilité stérilisation par ligne
//! d'acte (#4951, maquette design-v2 « Actes de la séance ») — vert
//! `verified` si l'acte est tracé (`ClinicalAct.sterilized`), sinon
//! `qr_code_scanner` ouvrant `SterilizationScanPage` pour CET acte (son
//! `id`, pas `session.acts.last` — voir le bouton global existant, #4139).

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/ccam_picker.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_bloc.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_event.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_page.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_state.dart';
import 'package:app_practicien/features/consultation_clinique/sterilization_scan_page.dart';

class MockConsultationCliniqueBloc
    extends MockBloc<ConsultationCliniqueEvent, ConsultationCliniqueState>
    implements ConsultationCliniqueBloc {}

class MockGetActsUseCase extends Mock implements GetActsUseCase {}

class MockFavoriteActsUseCase extends Mock implements FavoriteActsUseCase {}

class MockListSterilizationCycles extends Mock
    implements ListSterilizationCyclesUseCase {}

const _session = ClinicalSession(
  id: 's1',
  appointmentId: 'a1',
  status: 'in_progress',
  acts: [
    ClinicalAct(
      id: 'act-verified',
      ccamCode: 'HBLD038',
      label: 'Couronne',
      amountCents: 50000,
      sterilized: true,
    ),
    ClinicalAct(
      id: 'act-to-scan',
      ccamCode: 'HBLD745',
      label: 'Inlay-core',
      amountCents: 30000,
    ),
  ],
);

void main() {
  late MockConsultationCliniqueBloc bloc;
  late MockListSterilizationCycles listCycles;

  setUp(() {
    bloc = MockConsultationCliniqueBloc();
    when(() => bloc.state)
        .thenReturn(const ConsultationCliniqueLoaded(session: _session));
    whenListen(
      bloc,
      const Stream<ConsultationCliniqueState>.empty(),
      initialState: const ConsultationCliniqueLoaded(session: _session),
    );
    GetIt.instance.registerFactory<GetActsUseCase>(() => MockGetActsUseCase());
    final favoriteActs = MockFavoriteActsUseCase();
    when(() => favoriteActs.list()).thenAnswer((_) async => []);
    GetIt.instance.registerFactory<FavoriteActsUseCase>(() => favoriteActs);
    listCycles = MockListSterilizationCycles();
    when(() => listCycles()).thenAnswer((_) async => const Right([]));
    GetIt.instance
        .registerFactory<ListSterilizationCyclesUseCase>(() => listCycles);
    addTearDown(GetIt.instance.reset);
  });

  Widget buildBody() => MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: BlocProvider<ConsultationCliniqueBloc>.value(
            value: bloc,
            child: const ConsultationCliniqueBody(consultationId: 's1'),
          ),
        ),
      );

  testWidgets('acte tracé → pastille verte, non tapable', (tester) async {
    await tester.pumpWidget(buildBody());
    await tester.pump();

    final badge = find.byKey(const Key('sterilization_status_act-verified'));
    expect(badge, findsOneWidget);
    expect(
      find.descendant(of: badge, matching: find.byIcon(Icons.verified)),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('sterilization_scan_act_button_act-verified')),
      findsNothing,
    );
  });

  testWidgets(
      'acte non tracé → pastille « à scanner », tap ouvre le scan pour CET acte',
      (tester) async {
    await tester.pumpWidget(buildBody());
    await tester.pump();

    final badge = find.byKey(const Key('sterilization_status_act-to-scan'));
    expect(badge, findsOneWidget);
    expect(
      find.descendant(of: badge, matching: find.byIcon(Icons.qr_code_scanner)),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const Key('sterilization_scan_act_button_act-to-scan')),
    );
    await tester.tap(
        find.byKey(const Key('sterilization_scan_act_button_act-to-scan')));
    await tester.pumpAndSettle();

    final scanPage = tester.widget<SterilizationScanPage>(
      find.byType(SterilizationScanPage),
    );
    expect(scanPage.consultationActId, 'act-to-scan');
  });
}
