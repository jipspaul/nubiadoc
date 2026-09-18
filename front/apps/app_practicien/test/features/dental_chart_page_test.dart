//! Tests widget : `DentalChartPage` (#4047) — chargement, sélection d'état,
//! sauvegarde.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

  testWidgets(
      'patient sans odontogramme (updated_at null) : grille vierge + '
      'appel à l\'action, pas d\'écran d\'erreur (#6780)', (tester) async {
    // Modèle décodé depuis `{"teeth":{},"updated_at":null}` (API 200).
    when(() => getChart('pat-1')).thenAnswer(
      (_) async => const Right(DentalChart(teeth: {})),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dental_chart_error')), findsNothing);
    expect(find.text('Réessayer'), findsNothing);
    // Grille vierge complète : 32 dents adultes + bascule + Enregistrer.
    expect(find.byKey(const Key('dental_chart_tooth_11')), findsOneWidget);
    expect(find.byKey(const Key('dental_chart_tooth_48')), findsOneWidget);
    expect(find.byKey(const Key('dental_chart_adulte_toggle')), findsOneWidget);
    expect(find.byKey(const Key('dental_chart_enfant_toggle')), findsOneWidget);
    expect(find.byKey(const Key('dental_chart_save_button')), findsOneWidget);
    // Appel à l'action « premier schéma ».
    expect(find.byKey(const Key('dental_chart_blank_hint')), findsOneWidget);
  });

  testWidgets(
      'le premier enregistrement d\'un patient neuf retire l\'appel à '
      'l\'action (#6780)', (tester) async {
    when(() => getChart('pat-1')).thenAnswer(
      (_) async => const Right(DentalChart(teeth: {})),
    );
    when(() => putChart('pat-1', any())).thenAnswer(
      (_) async => Right(
        DentalChart(
          teeth: const {'11': ToothState(status: 'sain')},
          updatedAt: DateTime(2026, 9, 9),
        ),
      ),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dental_chart_blank_hint')), findsOneWidget);

    await tester.tap(find.byKey(const Key('dental_chart_tooth_11')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dental_chart_status_option_sain')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dental_chart_save_button')));
    await tester.pumpAndSettle();

    verify(() => putChart('pat-1', any())).called(1);
    expect(find.byKey(const Key('dental_chart_blank_hint')), findsNothing);
    expect(find.byKey(const Key('dental_chart_error')), findsNothing);
  });

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

  testWidgets(
      '#7297 : un 403 (pas de relation de soin) affiche un état explicite '
      'sans bouton Réessayer', (tester) async {
    when(() => getChart('pat-1')).thenAnswer(
      (_) async => const Left(ServerFailure(
        message: 'Aucune relation de soin avec ce patient.',
        statusCode: 403,
      )),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('dental_chart_access_denied')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('dental_chart_error')), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Réessayer'), findsNothing);
    expect(
      find.text('Accès clinique non autorisé pour ce rôle.'),
      findsNothing,
    );
  });

  testWidgets(
      'le statut clinique est porté par le libellé accessible, pas '
      'seulement la couleur (#7043)', (tester) async {
    when(() => getChart('pat-1')).thenAnswer(
      (_) async => Right(
        DentalChart(
          teeth: const {
            '11': ToothState(status: 'carie', plan: 'obture'),
            '21': ToothState(status: 'sain'),
          },
          updatedAt: DateTime(2026, 1, 1),
        ),
      ),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    SemanticsNode nodeOf(String key) =>
        tester.getSemantics(find.byKey(Key(key)));

    expect(nodeOf('dental_chart_tooth_11').label,
        'Dent 11 — Carie, plan : Obturée');
    expect(nodeOf('dental_chart_tooth_21').label, 'Dent 21 — Sain');
    // Dent sans statut : le libellé reste le numéro FDI seul.
    expect(nodeOf('dental_chart_tooth_12').label, 'Dent 12');
  });
}
