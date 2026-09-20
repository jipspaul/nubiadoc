import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/cabinet/act_categories_cubit.dart';
import 'package:app_practicien/features/cabinet/act_categories_page.dart';

class MockGetActCategoriesUseCase extends Mock
    implements GetActCategoriesUseCase {}

class MockUpdateActCategoriesUseCase extends Mock
    implements UpdateActCategoriesUseCase {}

const _categories = [
  ActCategorySetting(category: 'consultation', enabled: true),
  ActCategorySetting(category: 'ortho', enabled: true),
  ActCategorySetting(category: 'chirurgie', enabled: true),
  ActCategorySetting(category: 'imagerie', enabled: true),
];

void main() {
  setUpAll(() {
    registerFallbackValue(<ActCategorySetting>[]);
  });

  late MockGetActCategoriesUseCase mockGet;
  late MockUpdateActCategoriesUseCase mockUpdate;

  setUp(() {
    mockGet = MockGetActCategoriesUseCase();
    mockUpdate = MockUpdateActCategoriesUseCase();
    when(() => mockGet()).thenAnswer((_) async => const Right(_categories));

    GetIt.instance.registerFactory<ActCategoriesCubit>(
      () => ActCategoriesCubit(get: mockGet, update: mockUpdate),
    );
  });

  tearDown(() => GetIt.instance.reset());

  Widget wrap() => MaterialApp(
        theme: NubiaTheme.light,
        home: const ActCategoriesPage(),
      );

  testWidgets('affiche une bascule par catégorie renvoyée par l\'API',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Consultation'), findsOneWidget);
    expect(find.text('Orthodontie'), findsOneWidget);
    expect(find.text('Chirurgie'), findsOneWidget);
    expect(find.text('Imagerie'), findsOneWidget);
    for (final category in ['consultation', 'ortho', 'chirurgie', 'imagerie']) {
      expect(find.byKey(Key('act_category_$category')), findsOneWidget);
    }
  });

  testWidgets('bascule une catégorie déclenche un PUT avec la bonne valeur',
      (tester) async {
    when(() => mockUpdate(any()))
        .thenAnswer((_) async => const Right(_categories));

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final toggleFinder = find.byKey(const Key('act_category_chirurgie'));
    final before = tester.widget<NubiaToggle>(toggleFinder);
    expect(before.value, isTrue);

    await tester.tap(toggleFinder);
    await tester.pump();

    final captured = verify(() => mockUpdate.call(captureAny())).captured.last
        as List<ActCategorySetting>;
    final chirurgie = captured.firstWhere((c) => c.category == 'chirurgie');
    expect(chirurgie.enabled, isFalse);

    await tester.pumpAndSettle();
  });

  testWidgets(
      'preset « cabinet 100% ortho » masque toutes les catégories non ortho',
      (tester) async {
    when(() => mockUpdate(any())).thenAnswer(
      (invocation) async => Right(
          invocation.positionalArguments.first as List<ActCategorySetting>),
    );

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('full_ortho_preset_button')));
    await tester.pumpAndSettle();

    final captured = verify(() => mockUpdate.call(captureAny())).captured.last
        as List<ActCategorySetting>;
    for (final setting in captured) {
      expect(setting.enabled, setting.category == 'ortho');
    }

    expect(
      tester
          .widget<NubiaToggle>(find.byKey(const Key('act_category_ortho')))
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<NubiaToggle>(
            find.byKey(const Key('act_category_chirurgie')),
          )
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<NubiaToggle>(
            find.byKey(const Key('act_category_imagerie')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('rollback : un PUT en échec restaure le réglage précédent',
      (tester) async {
    when(() => mockUpdate(any()))
        .thenAnswer((_) async => const Left(ServerFailure(message: 'boom')));

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final toggleFinder = find.byKey(const Key('act_category_ortho'));
    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();

    expect(find.text('boom'), findsOneWidget);
    final after = tester.widget<NubiaToggle>(toggleFinder);
    expect(after.value, isTrue);
  });
}
