import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_practicien/features/consultation_clinique/ccam_picker.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetActsUseCase extends Mock implements GetActsUseCase {}

class MockFavoriteActsUseCase extends Mock implements FavoriteActsUseCase {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _actDetartrage = CcamAct(code: 'HBLD001', label: 'Détartrage');
const _actAvecTarif =
    CcamAct(code: 'HBGD036', label: 'Détartrage 2 arcades', tarifCents: 2864);

/// Acte soumis via l'éditeur (#3402).
class _Submitted {
  final String code;
  final String? tooth;
  final int amountCents;
  const _Submitted(this.code, this.tooth, this.amountCents);
}

Widget _wrap(
  GetActsUseCase useCase,
  void Function(_Submitted) onSubmitted, {
  String? selectedTooth,
  FavoriteActsUseCase? favoritesUseCase,
}) =>
    MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(
        body: CcamPicker(
          useCase: useCase,
          favoritesUseCase: favoritesUseCase,
          selectedTooth: selectedTooth,
          onActSubmitted: ({
            required String code,
            required String label,
            String? tooth,
            required int amountCents,
          }) =>
              onSubmitted(_Submitted(code, tooth, amountCents)),
        ),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('CcamPicker', () {
    late MockGetActsUseCase useCase;
    late List<_Submitted> submitted;

    setUp(() {
      useCase = MockGetActsUseCase();
      submitted = [];
    });

    testWidgets('≤3 lettres → search non appelée', (tester) async {
      await tester.pumpWidget(_wrap(useCase, submitted.add));

      await tester.enterText(find.byKey(const Key('ccam_search_field')), 'abc');
      await tester.pumpAndSettle();

      verifyNever(() => useCase.search(any()));
      expect(find.byKey(const Key('ccam_suggestions')), findsNothing);
    });

    testWidgets('sélection suggestion → ouvre l\'éditeur d\'acte (#3402)',
        (tester) async {
      when(() => useCase.search(any()))
          .thenAnswer((_) async => [_actDetartrage]);

      await tester.pumpWidget(_wrap(useCase, submitted.add));

      await tester.enterText(
          find.byKey(const Key('ccam_search_field')), 'déta');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ccam_act_HBLD001')));
      await tester.pumpAndSettle();

      // L'éditeur (dent + montant) s'ouvre — aucun acte envoyé sans saisie.
      expect(find.byKey(const Key('act_editor')), findsOneWidget);
      expect(find.byKey(const Key('act_editor_tooth_field')), findsOneWidget);
      expect(find.byKey(const Key('act_editor_amount_field')), findsOneWidget);
      expect(submitted, isEmpty);
    });

    testWidgets('éditeur : saisie dent + montant → callback (#3402)',
        (tester) async {
      when(() => useCase.search(any()))
          .thenAnswer((_) async => [_actDetartrage]);

      await tester.pumpWidget(_wrap(useCase, submitted.add));
      await tester.enterText(
          find.byKey(const Key('ccam_search_field')), 'déta');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ccam_act_HBLD001')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('act_editor_tooth_field')), '26');
      await tester.enterText(
          find.byKey(const Key('act_editor_amount_field')), '45,00');
      await tester.tap(find.byKey(const Key('act_editor_submit')));
      await tester.pumpAndSettle();

      expect(submitted, hasLength(1));
      expect(submitted.first.code, 'HBLD001');
      expect(submitted.first.tooth, '26');
      expect(submitted.first.amountCents, 4500);
    });

    testWidgets('éditeur : montant pré-rempli avec le tarif de référence',
        (tester) async {
      when(() => useCase.search(any()))
          .thenAnswer((_) async => [_actAvecTarif]);

      await tester.pumpWidget(_wrap(useCase, submitted.add));
      await tester.enterText(
          find.byKey(const Key('ccam_search_field')), 'déta');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ccam_act_HBGD036')));
      await tester.pumpAndSettle();

      // Le tarif 2864 cents est pré-rempli en « 28,64 » — soumission directe.
      expect(find.text('28,64'), findsOneWidget);
      await tester.tap(find.byKey(const Key('act_editor_submit')));
      await tester.pumpAndSettle();

      expect(submitted, hasLength(1));
      expect(submitted.first.amountCents, 2864);
      expect(submitted.first.tooth, isNull);
    });

    testWidgets('éditeur : annulation → aucun acte envoyé', (tester) async {
      when(() => useCase.search(any()))
          .thenAnswer((_) async => [_actDetartrage]);

      await tester.pumpWidget(_wrap(useCase, submitted.add));
      await tester.enterText(
          find.byKey(const Key('ccam_search_field')), 'déta');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ccam_act_HBLD001')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('act_editor_cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('act_editor')), findsNothing);
      expect(submitted, isEmpty);
    });

    testWidgets(
        'selectedTooth (#4048) → pré-remplit le champ dent de l\'éditeur',
        (tester) async {
      when(() => useCase.search(any()))
          .thenAnswer((_) async => [_actDetartrage]);

      await tester
          .pumpWidget(_wrap(useCase, submitted.add, selectedTooth: '26'));
      await tester.enterText(
          find.byKey(const Key('ccam_search_field')), 'déta');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ccam_act_HBLD001')));
      await tester.pumpAndSettle();

      final field = tester
          .widget<TextField>(find.descendant(
            of: find.byKey(const Key('act_editor_tooth_field')),
            matching: find.byType(TextField),
          ))
          .controller;
      expect(field?.text, '26');

      // Reste modifiable : soumission directe (dent pré-remplie) envoie bien
      // '26' une fois le montant saisi.
      await tester.enterText(
          find.byKey(const Key('act_editor_amount_field')), '10,00');
      await tester.tap(find.byKey(const Key('act_editor_submit')));
      await tester.pumpAndSettle();

      expect(submitted, hasLength(1));
      expect(submitted.first.tooth, '26');
    });

    testWidgets('aucun résultat → empty state affiché', (tester) async {
      when(() => useCase.search(any())).thenAnswer((_) async => []);

      await tester.pumpWidget(_wrap(useCase, submitted.add));

      await tester.enterText(
          find.byKey(const Key('ccam_search_field')), 'zzzz');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ccam_no_results')), findsOneWidget);
      expect(find.byKey(const Key('ccam_suggestions')), findsNothing);
    });

    testWidgets(
        'badge ⌘K visible sur le champ vide, masqué une fois la saisie '
        'commencée (#4941)', (tester) async {
      await tester.pumpWidget(_wrap(useCase, submitted.add));
      await tester.pumpAndSettle();

      expect(find.text('⌘K'), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('ccam_search_field')), 'a');
      await tester.pump();

      expect(find.text('⌘K'), findsNothing);
    });

    testWidgets('⌘K place le focus sur la recherche d\'acte (#4941)',
        (tester) async {
      await tester.pumpWidget(_wrap(useCase, submitted.add));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

      final focusNode = tester
          .widget<TextField>(find.descendant(
            of: find.byKey(const Key('ccam_search_field')),
            matching: find.byType(TextField),
          ))
          .focusNode;
      expect(focusNode?.hasFocus, isTrue);
    });

    testWidgets(
        '⌘K n\'intercepte pas la frappe normale de la lettre K (#4941)',
        (tester) async {
      when(() => useCase.search(any()))
          .thenAnswer((_) async => [_actDetartrage]);

      await tester.pumpWidget(_wrap(useCase, submitted.add));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('ccam_search_field')), 'kkkk');
      await tester.pumpAndSettle();

      verify(() => useCase.search('kkkk')).called(1);
    });
  });

  group('CcamPicker — favoris (#4113)', () {
    late MockGetActsUseCase useCase;
    late MockFavoriteActsUseCase favoritesUseCase;
    late List<_Submitted> submitted;

    setUp(() {
      useCase = MockGetActsUseCase();
      favoritesUseCase = MockFavoriteActsUseCase();
      submitted = [];
    });

    testWidgets('affiche la section favoris avant la recherche',
        (tester) async {
      when(() => favoritesUseCase.list())
          .thenAnswer((_) async => [_actDetartrage]);

      await tester.pumpWidget(
        _wrap(useCase, submitted.add, favoritesUseCase: favoritesUseCase),
      );
      await tester.pumpAndSettle();

      expect(find.text('Favoris'), findsOneWidget);
      expect(
        find.byKey(const Key('ccam_favorite_HBLD001')),
        findsOneWidget,
      );
    });

    testWidgets(
        'chip favori (#4969) : libellé + code CCAM, cible tactile ≥ 44px',
        (tester) async {
      when(() => favoritesUseCase.list())
          .thenAnswer((_) async => [_actDetartrage]);

      await tester.pumpWidget(
        _wrap(useCase, submitted.add, favoritesUseCase: favoritesUseCase),
      );
      await tester.pumpAndSettle();

      expect(find.text('Détartrage'), findsOneWidget);
      expect(find.text('HBLD001'), findsOneWidget);

      final chipHeight = tester
          .getSize(find.byKey(const Key('ccam_favorite_HBLD001')))
          .height;
      expect(chipHeight, greaterThanOrEqualTo(44));
    });

    testWidgets('aucun favori → section favoris absente', (tester) async {
      when(() => favoritesUseCase.list()).thenAnswer((_) async => []);

      await tester.pumpWidget(
        _wrap(useCase, submitted.add, favoritesUseCase: favoritesUseCase),
      );
      await tester.pumpAndSettle();

      expect(find.text('Favoris'), findsNothing);
      expect(find.byKey(const Key('ccam_favorites')), findsNothing);
    });

    testWidgets('tap sur un favori ouvre l\'éditeur d\'acte', (tester) async {
      when(() => favoritesUseCase.list())
          .thenAnswer((_) async => [_actDetartrage]);

      await tester.pumpWidget(
        _wrap(useCase, submitted.add, favoritesUseCase: favoritesUseCase),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ccam_favorite_HBLD001')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('act_editor')), findsOneWidget);
    });

    testWidgets(
        'désépingler depuis les résultats de recherche appelle remove() et '
        'recharge la liste', (tester) async {
      // Les chips favoris (#4969) sont des cibles tactiles d'ajout pur (sans
      // bouton épingle) ; le désépinglage reste possible depuis les
      // résultats de recherche, comme pour tout acte non favori.
      when(() => favoritesUseCase.list())
          .thenAnswer((_) async => [_actDetartrage]);
      when(() => useCase.search(any()))
          .thenAnswer((_) async => [_actDetartrage]);
      when(() => favoritesUseCase.remove('HBLD001')).thenAnswer((_) async {});

      await tester.pumpWidget(
        _wrap(useCase, submitted.add, favoritesUseCase: favoritesUseCase),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('ccam_search_field')), 'déta');
      await tester.pumpAndSettle();

      when(() => favoritesUseCase.list()).thenAnswer((_) async => []);
      await tester.tap(find.byKey(const Key('ccam_favorite_toggle_HBLD001')));
      await tester.pumpAndSettle();

      verify(() => favoritesUseCase.remove('HBLD001')).called(1);
      expect(find.text('Favoris'), findsNothing);
    });

    testWidgets(
        'épingler un résultat de recherche appelle add() et recharge la liste',
        (tester) async {
      when(() => favoritesUseCase.list()).thenAnswer((_) async => []);
      when(() => useCase.search(any()))
          .thenAnswer((_) async => [_actDetartrage]);
      when(() => favoritesUseCase.add('HBLD001')).thenAnswer((_) async {});

      await tester.pumpWidget(
        _wrap(useCase, submitted.add, favoritesUseCase: favoritesUseCase),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('ccam_search_field')), 'déta');
      await tester.pumpAndSettle();

      when(() => favoritesUseCase.list())
          .thenAnswer((_) async => [_actDetartrage]);
      await tester.tap(find.byKey(const Key('ccam_favorite_toggle_HBLD001')));
      await tester.pumpAndSettle();

      verify(() => favoritesUseCase.add('HBLD001')).called(1);
      // Épingler depuis la recherche n'ouvre pas l'éditeur d'acte (tap sur
      // le bouton épingle uniquement, pas sur la ligne).
      expect(find.byKey(const Key('act_editor')), findsNothing);
      expect(find.text('Favoris'), findsOneWidget);
    });
  });
}
