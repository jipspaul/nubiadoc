//! Tests widget : `DentalChartPage` (#4047) — chargement, sélection d'état,
//! sauvegarde.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/dental_chart/dental_chart_page.dart';

class _MockGetDentalChart extends Mock implements GetDentalChartUseCase {}

class _MockPutDentalChart extends Mock implements PutDentalChartUseCase {}

void main() {
  late _MockGetDentalChart getChart;
  late _MockPutDentalChart putChart;

  setUp(() {
    getChart = _MockGetDentalChart();
    putChart = _MockPutDentalChart();
    GetIt.instance.registerFactory<GetDentalChartUseCase>(() => getChart);
    GetIt.instance.registerFactory<PutDentalChartUseCase>(() => putChart);
    addTearDown(GetIt.instance.reset);
  });

  Widget buildPage() => MaterialApp(
        theme: NubiaTheme.light,
        home: const DentalChartPage(patientId: 'pat-1'),
      );

  testWidgets('charge et affiche les dents avec leur état', (tester) async {
    when(() => getChart('pat-1')).thenAnswer(
      (_) async => Right(
        DentalChart(
          teeth: const {'11': ToothState(status: 'carie')},
          updatedAt: DateTime(2026, 1, 1),
        ),
      ),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dental_chart_tooth_11')), findsOneWidget);
    // Bouton Enregistrer désactivé tant qu'aucune modification locale.
    final saveButton = tester.widget<NubiaButton>(
      find.byKey(const Key('dental_chart_save_button')),
    );
    expect(saveButton.onPressed, isNull);
  });

  testWidgets(
      'taper une dent puis choisir un état active le bouton Enregistrer',
      (tester) async {
    when(() => getChart('pat-1')).thenAnswer(
      (_) async => Right(
        DentalChart(teeth: const {}, updatedAt: DateTime(2026, 1, 1)),
      ),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dental_chart_tooth_11')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dental_chart_status_option_carie')));
    await tester.pumpAndSettle();

    final saveButton = tester.widget<NubiaButton>(
      find.byKey(const Key('dental_chart_save_button')),
    );
    expect(saveButton.onPressed, isNotNull);
  });

  testWidgets('Enregistrer appelle PutDentalChartUseCase avec le nouvel état',
      (tester) async {
    when(() => getChart('pat-1')).thenAnswer(
      (_) async => Right(
        DentalChart(teeth: const {}, updatedAt: DateTime(2026, 1, 1)),
      ),
    );
    when(() => putChart('pat-1', any())).thenAnswer(
      (_) async => Right(
        DentalChart(
          teeth: const {'11': ToothState(status: 'carie')},
          updatedAt: DateTime(2026, 1, 2),
        ),
      ),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dental_chart_tooth_11')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dental_chart_status_option_carie')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dental_chart_save_button')));
    await tester.pumpAndSettle();

    final captured = verify(() => putChart('pat-1', captureAny()))
        .captured
        .single as Map<String, ToothState>;
    expect(captured['11']?.status, 'carie');
  });

  testWidgets('denture Enfant affiche les codes de dents lait', (tester) async {
    when(() => getChart('pat-1')).thenAnswer(
      (_) async => Right(
        DentalChart(teeth: const {}, updatedAt: DateTime(2026, 1, 1)),
      ),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dental_chart_tooth_55')), findsNothing);

    await tester.tap(find.byKey(const Key('dental_chart_enfant_toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dental_chart_tooth_55')), findsOneWidget);
    expect(find.byKey(const Key('dental_chart_tooth_11')), findsNothing);
  });
}
