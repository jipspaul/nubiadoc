//! Tests widget : `PeriodontalChartPage` (#4106) — chargement, saisie d'une
//! profondeur de sondage, ajout d'un indice, sauvegarde.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/periodontal_chart/periodontal_chart_page.dart';

class _MockGetPeriodontalChart extends Mock
    implements GetPeriodontalChartUseCase {}

class _MockPutPeriodontalChart extends Mock
    implements PutPeriodontalChartUseCase {}

void main() {
  late _MockGetPeriodontalChart getChart;
  late _MockPutPeriodontalChart putChart;

  setUp(() {
    getChart = _MockGetPeriodontalChart();
    putChart = _MockPutPeriodontalChart();
    GetIt.instance.registerFactory<GetPeriodontalChartUseCase>(() => getChart);
    GetIt.instance.registerFactory<PutPeriodontalChartUseCase>(() => putChart);
    addTearDown(GetIt.instance.reset);
  });

  Widget buildPage() => MaterialApp(
        theme: NubiaTheme.light,
        home: const PeriodontalChartPage(patientId: 'pat-1'),
      );

  testWidgets('charge et affiche les 32 dents adultes', (tester) async {
    when(() => getChart('pat-1')).thenAnswer(
      (_) async => Right(
        PeriodontalChart(
          sites: const {},
          indices: const {},
          measuredAt: DateTime(2026, 1, 1),
        ),
      ),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('periodontal_chart_tooth_11')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('periodontal_chart_tooth_48')),
      findsOneWidget,
    );
    final saveButton = tester.widget<NubiaButton>(
      find.byKey(const Key('periodontal_chart_save_button')),
    );
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('saisir une profondeur de sondage active Enregistrer',
      (tester) async {
    when(() => getChart('pat-1')).thenAnswer(
      (_) async => Right(
        PeriodontalChart(
          sites: const {},
          indices: const {},
          measuredAt: DateTime(2026, 1, 1),
        ),
      ),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    final tile = find.byKey(const Key('periodontal_chart_tooth_11_tile'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('periodontal_chart_11_MV'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '3');
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const Key('periodontal_chart_save_button'));
    await tester.ensureVisible(saveButton);
    expect(tester.widget<NubiaButton>(saveButton).onPressed, isNotNull);
  });

  testWidgets('Enregistrer appelle PutPeriodontalChartUseCase', (tester) async {
    when(() => getChart('pat-1')).thenAnswer(
      (_) async => Right(
        PeriodontalChart(
          sites: const {},
          indices: const {},
          measuredAt: DateTime(2026, 1, 1),
        ),
      ),
    );
    when(() => putChart('pat-1', any(), any())).thenAnswer(
      (_) async => Right(
        PeriodontalChart(
          sites: const {'11': ToothSiteDepths(mv: 3)},
          indices: const {},
          measuredAt: DateTime(2026, 1, 2),
        ),
      ),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    final tile = find.byKey(const Key('periodontal_chart_tooth_11_tile'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('periodontal_chart_11_MV'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '3');
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const Key('periodontal_chart_save_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final captured = verify(
      () => putChart('pat-1', captureAny(), any()),
    ).captured.single as Map<String, ToothSiteDepths>;
    expect(captured['11']?.mv, 3);
  });

  testWidgets('ajouter un indice clinique met à jour la liste', (tester) async {
    when(() => getChart('pat-1')).thenAnswer(
      (_) async => Right(
        PeriodontalChart(
          sites: const {},
          indices: const {},
          measuredAt: DateTime(2026, 1, 1),
        ),
      ),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    final nameField = find.byKey(const Key('periodontal_chart_new_index_name'));
    await tester.ensureVisible(nameField);
    await tester.enterText(nameField, 'Indice de plaque');

    final valueField =
        find.byKey(const Key('periodontal_chart_new_index_value'));
    await tester.ensureVisible(valueField);
    await tester.enterText(valueField, '12.5');

    final addButton =
        find.byKey(const Key('periodontal_chart_add_index_button'));
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(find.text('Indice de plaque'), findsOneWidget);
    final saveButton = find.byKey(const Key('periodontal_chart_save_button'));
    await tester.ensureVisible(saveButton);
    expect(tester.widget<NubiaButton>(saveButton).onPressed, isNotNull);
  });
}
