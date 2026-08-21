import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/notification_prefs/notification_prefs_cubit.dart';
import 'package:app_patient/features/notification_prefs/notification_prefs_page.dart';

class MockGetNotificationPreferencesUseCase extends Mock
    implements GetNotificationPreferencesUseCase {}

class MockUpdateNotificationPreferencesUseCase extends Mock
    implements UpdateNotificationPreferencesUseCase {}

const _prefs = NotificationPreferences(
  pushEnabled: true,
  emailEnabled: true,
  smsEnabled: true,
  appointments: true,
  documents: true,
  messages: true,
  payments: true,
  prevention: true,
);

void main() {
  setUpAll(() {
    registerFallbackValue(const NotificationPreferences.allEnabled());
  });

  late MockGetNotificationPreferencesUseCase mockGet;
  late MockUpdateNotificationPreferencesUseCase mockUpdate;

  setUp(() {
    mockGet = MockGetNotificationPreferencesUseCase();
    mockUpdate = MockUpdateNotificationPreferencesUseCase();
    when(() => mockGet()).thenAnswer((_) async => const Right(_prefs));
    when(() => mockUpdate(any())).thenAnswer((_) async => const Right(null));

    GetIt.instance.registerFactory<NotificationPrefsCubit>(
      () => NotificationPrefsCubit(get: mockGet, update: mockUpdate),
    );
  });

  tearDown(() => GetIt.instance.reset());

  Widget wrap() => MaterialApp(
        theme: NubiaTheme.light,
        home: const NotificationPrefsPage(),
      );

  testWidgets(
      'la bascule RDV est verrouillée activée avec le badge "Toujours activé"',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final toggleFinder = find.byKey(const Key('notif_appointments'));
    expect(toggleFinder, findsOneWidget);

    final toggle = tester.widget<SwitchListTile>(toggleFinder);
    expect(toggle.value, isTrue);
    expect(toggle.onChanged, isNull);

    expect(find.text('Toujours activé'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsOneWidget);
  });

  testWidgets('le canal push reste actionnable indépendamment',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notif_push')));
    await tester.pumpAndSettle();

    final captured = verify(
      () => mockUpdate.call(captureAny()),
    ).captured;
    final updated = captured.last as NotificationPreferences;
    expect(updated.pushEnabled, isFalse);
    expect(updated.appointments, isTrue);
  });
}
