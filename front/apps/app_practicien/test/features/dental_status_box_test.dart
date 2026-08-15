//! Tests widget : `DentalStatusBox` (#4949) — arcade permanente de la
//! colonne centrale de la consultation PC, colorée par statut + légende.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/widgets/dental_status_box.dart';
import 'package:app_practicien/features/dental_chart/tooth_grid.dart';

class _MockGetDentalChart extends Mock implements GetDentalChartUseCase {}

void main() {
  late _MockGetDentalChart getChart;

  setUp(() {
    getChart = _MockGetDentalChart();
    GetIt.instance.registerFactory<GetDentalChartUseCase>(() => getChart);
    addTearDown(GetIt.instance.reset);
  });

  Widget buildBox({
    String? selectedTooth,
    ValueChanged<String>? onToothTap,
    List<ClinicalAct> sessionActs = const [],
  }) =>
      MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: DentalStatusBox(
            patientId: 'pat-1',
            sessionActs: sessionActs,
            selectedTooth: selectedTooth,
            onToothTap: onToothTap ?? (_) {},
          ),
        ),
      );

  testWidgets('arcade visible en permanence avec titre et légende',
      (tester) async {
    when(() => getChart('pat-1')).thenAnswer(
      (_) async =>
          Right(DentalChart(teeth: const {}, updatedAt: DateTime(2026, 1, 1))),
    );

    await tester.pumpWidget(buildBox());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dental_status_box')), findsOneWidget);
    expect(find.text('Schéma dentaire'), findsOneWidget);
    expect(find.byKey(const Key('consultation_tooth_11')), findsOneWidget);
    expect(find.text('Acte de la séance'), findsOneWidget);
    expect(find.text('Soin antérieur'), findsOneWidget);
    expect(find.text('À surveiller'), findsOneWidget);
    expect(find.text('Saine'), findsOneWidget);
  });

  testWidgets(
      'colore par statut : acte de la séance, antérieur, à surveiller, saine',
      (tester) async {
    when(() => getChart('pat-1')).thenAnswer(
      (_) async => Right(
        DentalChart(
          teeth: const {
            '17': ToothState(status: 'obture'),
            '14': ToothState(status: 'carie'),
          },
          updatedAt: DateTime(2026, 1, 1),
        ),
      ),
    );

    await tester.pumpWidget(buildBox(
      sessionActs: const [
        ClinicalAct(id: 'a1', ccamCode: 'X', label: 'Soin', tooth: '26'),
      ],
    ));
    await tester.pumpAndSettle();

    final cs = NubiaTheme.light.colorScheme;

    Color colorOf(String code) =>
        tester.widget<ToothButton>(find.byKey(Key('consultation_tooth_$code')))
            .color;

    expect(colorOf('26'), cs.primary); // acte de la séance
    expect(colorOf('17'), NubiaColors.n100); // soin antérieur
    expect(colorOf('14'), NubiaColors.warningBg); // à surveiller
    expect(colorOf('11'), NubiaColors.n0); // saine
  });

  testWidgets('un tap sur une dent la sélectionne (comportement toggle)',
      (tester) async {
    when(() => getChart('pat-1')).thenAnswer(
      (_) async =>
          Right(DentalChart(teeth: const {}, updatedAt: DateTime(2026, 1, 1))),
    );
    String? tapped;

    await tester.pumpWidget(
      buildBox(onToothTap: (code) => tapped = code),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('consultation_tooth_26')));
    await tester.pumpAndSettle();

    expect(tapped, '26');
  });

  testWidgets('la dent sélectionnée a un contour épais', (tester) async {
    when(() => getChart('pat-1')).thenAnswer(
      (_) async =>
          Right(DentalChart(teeth: const {}, updatedAt: DateTime(2026, 1, 1))),
    );

    await tester.pumpWidget(buildBox(selectedTooth: '26'));
    await tester.pumpAndSettle();

    final selected = tester
        .widget<ToothButton>(find.byKey(const Key('consultation_tooth_26')));
    final other = tester
        .widget<ToothButton>(find.byKey(const Key('consultation_tooth_11')));
    expect(selected.selected, isTrue);
    expect(other.selected, isFalse);
  });
}
