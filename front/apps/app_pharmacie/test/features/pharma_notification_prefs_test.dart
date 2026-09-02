import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_pharmacie/features/notification_prefs/pharma_notification_prefs_cubit.dart';
import 'package:app_pharmacie/features/notification_prefs/pharma_notification_prefs_page.dart';

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

    GetIt.instance.registerFactory<PharmaNotificationPrefsCubit>(
      () => PharmaNotificationPrefsCubit(get: mockGet, update: mockUpdate),
    );
  });

  tearDown(() => GetIt.instance.reset());

  Widget wrap() => MaterialApp(
        theme: NubiaTheme.light,
        home: const PharmaNotificationPrefsPage(),
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

  testWidgets('affiche les 3 catégories pertinentes pour le rôle pharmacie',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Messagerie'), findsOneWidget);
    expect(find.text('Devis'), findsOneWidget);
    expect(find.text('Demandes de stock'), findsOneWidget);
  });

  testWidgets('la catégorie stock n\'a pas de bascule e-mail (pas de champ API)',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await scrollTo(tester, find.byKey(const Key('pharma_notif_block_stock')));
    expect(find.byKey(const Key('pharma_notif_inapp_stock')), findsOneWidget);
    expect(find.byKey(const Key('pharma_notif_email_stock')), findsNothing);
  });

  testWidgets(
      'toggle in-app messagerie déclenche un PATCH optimiste avec la bonne valeur',
      (tester) async {
    when(() => mockUpdate(any())).thenAnswer((_) async => const Right(_prefs));

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final toggleFinder = find.byKey(const Key('pharma_notif_inapp_messagerie'));
    final before = tester.widget<NubiaToggle>(toggleFinder);
    expect(before.value, isTrue);

    await tester.tap(toggleFinder);
    await tester.pump();

    final captured =
        verify(() => mockUpdate.call(captureAny())).captured.last
            as ProNotificationPreferences;
    expect(captured.inappMessagerie, isFalse);

    await tester.pumpAndSettle();
  });

  testWidgets('toggle email devis persiste et se reflète après un re-GET',
      (tester) async {
    when(() => mockUpdate(any())).thenAnswer(
      (invocation) async =>
          Right(invocation.positionalArguments.first as ProNotificationPreferences),
    );

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final toggleFinder = find.byKey(const Key('pharma_notif_email_devis'));
    await scrollTo(tester, toggleFinder);
    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();

    final saved =
        verify(() => mockUpdate.call(captureAny())).captured.last
            as ProNotificationPreferences;
    expect(saved.emailDevis, isTrue);

    // Simule le serveur ayant persisté le PATCH : le prochain GET renvoie
    // désormais `emailDevis: true`.
    when(() => mockGet()).thenAnswer((_) async => Right(saved));

    final cubit = tester
        .element(find.byKey(const Key('pharma_notif_prefs_list')))
        .read<PharmaNotificationPrefsCubit>();
    await cubit.load();
    await tester.pumpAndSettle();

    final reloaded = tester.widget<NubiaToggle>(
      find.byKey(const Key('pharma_notif_email_devis')),
    );
    expect(reloaded.value, isTrue);
  });

  testWidgets('rollback : un PATCH en échec restaure la valeur précédente',
      (tester) async {
    when(() => mockUpdate(any()))
        .thenAnswer((_) async => const Left(ServerFailure(message: 'boom')));

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final toggleFinder = find.byKey(const Key('pharma_notif_inapp_stock'));
    await scrollTo(tester, toggleFinder);

    final before = tester.widget<NubiaToggle>(toggleFinder);
    expect(before.value, isTrue);

    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();

    expect(find.text('boom'), findsOneWidget);

    final after = tester.widget<NubiaToggle>(
      find.byKey(const Key('pharma_notif_inapp_stock')),
    );
    expect(after.value, isTrue);
  });
}
