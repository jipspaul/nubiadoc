import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_infirmiere/features/notification_prefs/notification_prefs_cubit.dart';
import 'package:app_infirmiere/features/notification_prefs/notification_prefs_page.dart';

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

  testWidgets('affiche la catégorie Visites avec in-app et push (#6341)',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Visites'), findsOneWidget);
    expect(find.byKey(const Key('notif_inapp_visites')), findsOneWidget);
    expect(find.byKey(const Key('notif_push_visites')), findsOneWidget);
    // Pas de canal e-mail côté API pour cette catégorie.
    expect(find.byKey(const Key('notif_email_visites')), findsNothing);
  });

  testWidgets(
      'toggle push visites déclenche un PATCH optimiste avec la bonne valeur',
      (tester) async {
    when(() => mockUpdate(any())).thenAnswer((_) async => const Right(_prefs));

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final toggleFinder = find.byKey(const Key('notif_push_visites'));
    final before = tester.widget<NubiaToggle>(toggleFinder);
    expect(before.value, isTrue);

    await tester.tap(toggleFinder);
    await tester.pump();

    final captured =
        verify(() => mockUpdate.call(captureAny())).captured.last
            as ProNotificationPreferences;
    expect(captured.pushVisites, isFalse);

    await tester.pumpAndSettle();
  });

  testWidgets('rollback : un PATCH en échec restaure la valeur précédente',
      (tester) async {
    when(() => mockUpdate(any()))
        .thenAnswer((_) async => const Left(ServerFailure(message: 'boom')));

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final toggleFinder = find.byKey(const Key('notif_inapp_visites'));
    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();

    expect(find.text('boom'), findsOneWidget);

    final after = tester.widget<NubiaToggle>(toggleFinder);
    expect(after.value, isTrue);
  });
}
