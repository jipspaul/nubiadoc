import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/notification_prefs/notification_prefs_cubit.dart';
import 'package:app_practicien/features/notification_prefs/notification_prefs_page.dart';

class MockGetProNotificationPreferencesUseCase extends Mock
    implements GetProNotificationPreferencesUseCase {}

class MockUpdateProNotificationPreferencesUseCase extends Mock
    implements UpdateProNotificationPreferencesUseCase {}

const _prefs = ProNotificationPreferences(
  inappRdv: true,
  inappMessagerie: true,
  inappDevis: true,
  inappStock: true,
  inappLabo: true,
  inappVisites: true,
  emailRdv: false,
  emailMessagerie: false,
  emailDevis: false,
  pushRdv: true,
  pushMessagerie: true,
  pushDevis: true,
  pushStock: true,
  pushLabo: true,
  pushVisites: true,
);

void main() {
  setUpAll(() {
    registerFallbackValue(const ProNotificationPreferences.defaults());
  });

  late MockGetProNotificationPreferencesUseCase mockGet;
  late MockUpdateProNotificationPreferencesUseCase mockUpdate;

  setUp(() {
    mockGet = MockGetProNotificationPreferencesUseCase();
    mockUpdate = MockUpdateProNotificationPreferencesUseCase();
    when(() => mockGet()).thenAnswer((_) async => const Right(_prefs));

    GetIt.instance.registerFactory<NotificationPrefsCubit>(
      () => NotificationPrefsCubit(get: mockGet, update: mockUpdate),
    );
  });

  tearDown(() => GetIt.instance.reset());

  Widget wrap() => MaterialApp(
        theme: NubiaTheme.light,
        home: const NotificationPrefsPage(),
      );

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'affiche les 5 catégories pertinentes pour le rôle praticien (#6341)',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Rendez-vous'), findsOneWidget);
    expect(find.text('Messagerie'), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('notif_block_devis')));
    expect(find.text('Devis'), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('notif_block_labo')));
    expect(find.text('Travaux de laboratoire'), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('notif_block_stock')));
    expect(find.text('Demandes de stock'), findsOneWidget);
  });

  testWidgets('chaque catégorie expose une bascule push (#6341)',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    for (final key in [
      'notif_push_rdv',
      'notif_push_messagerie',
      'notif_push_devis',
      'notif_push_labo',
      'notif_push_stock',
    ]) {
      final finder = find.byKey(Key(key));
      await scrollTo(tester, finder);
      expect(finder, findsOneWidget);
    }
  });

  testWidgets(
      'toggle push rdv déclenche un PATCH optimiste avec la bonne valeur',
      (tester) async {
    when(() => mockUpdate(any())).thenAnswer((_) async => const Right(_prefs));

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final toggleFinder = find.byKey(const Key('notif_push_rdv'));
    final before = tester.widget<NubiaToggle>(toggleFinder);
    expect(before.value, isTrue);

    await tester.tap(toggleFinder);
    await tester.pump();

    final captured =
        verify(() => mockUpdate.call(captureAny())).captured.last
            as ProNotificationPreferences;
    expect(captured.pushRdv, isFalse);

    await tester.pumpAndSettle();
  });

  testWidgets('rollback : un PATCH en échec restaure la valeur précédente',
      (tester) async {
    when(() => mockUpdate(any()))
        .thenAnswer((_) async => const Left(ServerFailure(message: 'boom')));

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final toggleFinder = find.byKey(const Key('notif_push_stock'));
    await scrollTo(tester, toggleFinder);

    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();

    expect(find.text('boom'), findsOneWidget);

    final after = tester.widget<NubiaToggle>(toggleFinder);
    expect(after.value, isTrue);
  });
}
