import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_practicien/features/consultation_clinique/ccam_picker.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetActsUseCase extends Mock implements GetActsUseCase {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _actDetartrage = CcamAct(code: 'HBLD001', label: 'Détartrage');

Widget _wrap(GetActsUseCase useCase, void Function(CcamAct) onSelected) =>
    MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(
        body: CcamPicker(useCase: useCase, onActSelected: onSelected),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('CcamPicker', () {
    late MockGetActsUseCase useCase;
    late List<CcamAct> selected;

    setUp(() {
      useCase = MockGetActsUseCase();
      selected = [];
    });

    testWidgets('≤2 lettres → search non appelée', (tester) async {
      await tester.pumpWidget(_wrap(useCase, selected.add));

      await tester.enterText(find.byKey(const Key('ccam_search_field')), 'ab');
      await tester.pumpAndSettle();

      verifyNever(() => useCase.search(any()));
      expect(find.byKey(const Key('ccam_suggestions')), findsNothing);
    });

    testWidgets('sélection suggestion → callback appelée', (tester) async {
      when(() => useCase.search(any()))
          .thenAnswer((_) async => [_actDetartrage]);

      await tester.pumpWidget(_wrap(useCase, selected.add));

      await tester.enterText(
          find.byKey(const Key('ccam_search_field')), 'déta');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ccam_act_HBLD001')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ccam_act_HBLD001')));
      await tester.pumpAndSettle();

      expect(selected, [_actDetartrage]);
    });

    testWidgets('aucun résultat → empty state affiché', (tester) async {
      when(() => useCase.search(any())).thenAnswer((_) async => []);

      await tester.pumpWidget(_wrap(useCase, selected.add));

      await tester.enterText(
          find.byKey(const Key('ccam_search_field')), 'zzzz');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ccam_no_results')), findsOneWidget);
      expect(find.byKey(const Key('ccam_suggestions')), findsNothing);
    });
  });
}
