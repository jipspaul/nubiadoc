//! Tests widget : odontogramme intégré à la vue fauteuil (module dentaire,
//! refonte lot 3 — tap dent → sélection pour l'acte, couleurs d'état réel,
//! marqueur sur les dents traitées cette séance).

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/consultation_clinique_bloc.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_event.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_state.dart';
import 'package:app_practicien/features/consultation_clinique/modules/dentaire/odontogram_panel.dart';
import 'package:app_practicien/features/dental_chart/dental_chart_cubit.dart';
import 'package:app_practicien/features/dental_chart/dental_chart_page.dart'
    show kToothStatusColors;
import 'package:app_practicien/features/dental_chart/tooth_grid.dart';

class MockConsultationCliniqueBloc
    extends MockBloc<ConsultationCliniqueEvent, ConsultationCliniqueState>
    implements ConsultationCliniqueBloc {}

class MockGetDentalChartUseCase extends Mock implements GetDentalChartUseCase {}

class MockPutDentalChartUseCase extends Mock implements PutDentalChartUseCase {}

const _session = ClinicalSession(
  id: 's1',
  appointmentId: 'a1',
  status: 'in_progress',
  acts: [
    ClinicalAct(
        id: 'act-1', ccamCode: 'HBLD036', label: 'Implant', tooth: '36'),
  ],
);

void main() {
  late MockConsultationCliniqueBloc bloc;
  late DentalChartCubit chartCubit;

  setUp(() {
    bloc = MockConsultationCliniqueBloc();
    final getChart = MockGetDentalChartUseCase();
    when(() => getChart.call(any())).thenAnswer(
      (_) async => Right(DentalChart(
        teeth: const {'26': ToothState(status: 'carie')},
        updatedAt: DateTime(2026, 8, 3),
      )),
    );
    chartCubit = DentalChartCubit(
      patientId: 'pt1',
      getDentalChart: getChart,
      putDentalChart: MockPutDentalChartUseCase(),
    );
  });

  tearDown(() => chartCubit.close());

  Future<void> pump(WidgetTester tester,
      {ConsultationCliniqueLoaded? state}) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Mock frais à chaque pump : whenListen ne re-stubbe pas correctement
    // `state` sur un mock déjà écouté.
    bloc = MockConsultationCliniqueBloc();
    final initial =
        state ?? const ConsultationCliniqueLoaded(session: _session);
    whenListen(
      bloc,
      const Stream<ConsultationCliniqueState>.empty(),
      initialState: initial,
    );

    await tester.pumpWidget(MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ConsultationCliniqueBloc>.value(value: bloc),
              BlocProvider<DentalChartCubit>.value(value: chartCubit),
            ],
            child: const OdontogramPanel(),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('colore les dents selon l\'état réel du patient', (tester) async {
    await pump(tester);

    final carieTooth = tester
        .widget<ToothButton>(find.byKey(const Key('odontogram_tooth_26')));
    expect(carieTooth.color, kToothStatusColors['carie']);

    final sainTooth = tester
        .widget<ToothButton>(find.byKey(const Key('odontogram_tooth_11')));
    expect(sainTooth.color, isNot(kToothStatusColors['carie']));
  });

  testWidgets('tap sur une dent → ToothSelected ; re-tap → ToothCleared',
      (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('odontogram_tooth_26')));
    verify(() => bloc.add(const ConsultationCliniqueToothSelected('26')))
        .called(1);

    // Même dent déjà sélectionnée dans l'état → désélection.
    await pump(tester,
        state: const ConsultationCliniqueLoaded(
            session: _session, selectedTooth: '26'));
    await tester.tap(find.byKey(const Key('odontogram_tooth_26')));
    verify(() => bloc.add(const ConsultationCliniqueToothCleared())).called(1);
  });

  testWidgets('dent sélectionnée : surbrillance + chip de désélection',
      (tester) async {
    await pump(tester,
        state: const ConsultationCliniqueLoaded(
            session: _session, selectedTooth: '26'));

    final tooth = tester
        .widget<ToothButton>(find.byKey(const Key('odontogram_tooth_26')));
    expect(tooth.selected, isTrue);
    expect(find.byKey(const Key('odontogram_selected_chip')), findsOneWidget);
  });

  testWidgets('les dents traitées cette séance portent un marqueur',
      (tester) async {
    await pump(tester);

    final treated = tester
        .widget<ToothButton>(find.byKey(const Key('odontogram_tooth_36')));
    expect(treated.showDot, isTrue);

    final untouched = tester
        .widget<ToothButton>(find.byKey(const Key('odontogram_tooth_11')));
    expect(untouched.showDot, isFalse);
  });

  testWidgets('légende : uniquement les statuts présents', (tester) async {
    await pump(tester);

    expect(find.byKey(const Key('odontogram_legend')), findsOneWidget);
    expect(find.text('Carie'), findsOneWidget);
    expect(find.text('Implant'), findsNothing);
  });
}
