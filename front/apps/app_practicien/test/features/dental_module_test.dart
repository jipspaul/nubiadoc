//! Tests : le module dentaire remplit chaque slot de
//! ConsultationSpecialtyModule (refonte consultation, lot 5).

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/modules/dentaire/dental_module.dart';
import 'package:app_practicien/features/consultation_clinique/modules/dentaire/odontogram_panel.dart';
import 'package:app_practicien/features/consultation_clinique/modules/dentaire/treated_tooth_tile.dart';

class MockGetDentalChartUseCase extends Mock implements GetDentalChartUseCase {}

class MockPutDentalChartUseCase extends Mock implements PutDentalChartUseCase {}

void main() {
  const module = DentalConsultationModule();

  setUp(() {
    final getChart = MockGetDentalChartUseCase();
    when(() => getChart.call(any())).thenAnswer(
      (_) async => Right(DentalChart(
        teeth: const {'26': ToothState(status: 'carie')},
        updatedAt: DateTime(2026, 8, 3),
      )),
    );
    GetIt.instance.registerFactory<GetDentalChartUseCase>(() => getChart);
    GetIt.instance
        .registerFactory<PutDentalChartUseCase>(MockPutDentalChartUseCase.new);
    addTearDown(GetIt.instance.reset);
  });

  test('slots : panneau central, tuile contexte (null sans dent)', () {
    final context = _FakeContext();
    expect(module.buildCentralPanel(context), isA<OdontogramPanel>());
    expect(module.buildContextTile(context, '26'), isA<TreatedToothTile>());
    expect(module.buildContextTile(context, null), isNull);
  });

  testWidgets(
      'wrapSession fournit le DentalChartCubit et teethStatus expose '
      'l\'état chargé', (tester) async {
    Map<String, ToothState>? seen;
    await tester.pumpWidget(MaterialApp(
      theme: NubiaTheme.light,
      home: module.wrapSession(
        patientId: 'pt1',
        child: Builder(
          builder: (context) {
            seen = module.teethStatus(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    ));
    // 1er build : chargement en cours → null (la vue tolère l'absence).
    expect(seen, isNull);
    await tester.pumpAndSettle();
    expect(seen?['26']?.status, 'carie');
  });
}

class _FakeContext extends Fake implements BuildContext {}
