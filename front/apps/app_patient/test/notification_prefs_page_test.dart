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
  messages: false,
  payments: false,
  prevention: false,
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

  /// La `ListView` de blocs dépasse la hauteur visible du banc de test :
  /// on scrolle jusqu'à révéler l'élément avant de le chercher/tapoter.
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
      'la bascule RDV est verrouillée activée avec le badge "Toujours activé"',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final toggleFinder = find.byKey(const Key('notif_appointments'));
    expect(toggleFinder, findsOneWidget);

    final toggle = tester.widget<NubiaToggle>(toggleFinder);
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

  testWidgets('les quatre blocs thématiques sont affichés avec leurs icônes',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notif_block_appointments')), findsOneWidget);
    expect(find.text('Rendez-vous'), findsOneWidget);
    expect(find.byIcon(Icons.event), findsOneWidget);

    await scrollTo(tester, find.byKey(const Key('notif_block_care')));
    expect(find.byKey(const Key('notif_block_care')), findsOneWidget);
    expect(find.text('Mes soins'), findsOneWidget);
    expect(find.byIcon(Icons.medical_services), findsOneWidget);

    await scrollTo(tester, find.byKey(const Key('notif_block_billing')));
    expect(find.byKey(const Key('notif_block_billing')), findsOneWidget);
    expect(find.text('Devis et paiements'), findsOneWidget);
    expect(find.byIcon(Icons.payments), findsOneWidget);

    await scrollTo(tester, find.byKey(const Key('notif_block_practice')));
    expect(find.byKey(const Key('notif_block_practice')), findsOneWidget);
    expect(find.text('Le cabinet'), findsOneWidget);
    expect(find.byIcon(Icons.campaign), findsOneWidget);
  });

  testWidgets(
      'la bascule "Actualités et prévention" est désactivée par défaut '
      'et se sauvegarde via le cubit', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final toggleFinder = find.byKey(const Key('notif_prevention'));
    await scrollTo(tester, toggleFinder);
    final toggle = tester.widget<NubiaToggle>(toggleFinder);
    expect(toggle.value, isFalse);

    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();

    final captured = verify(
      () => mockUpdate.call(captureAny()),
    ).captured;
    final updated = captured.last as NotificationPreferences;
    expect(updated.prevention, isTrue);
  });

  testWidgets(
      'les bascules "Mes soins" et "Devis et paiements" reflètent et '
      'sauvegardent leur champ NotificationPreferences dédié',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await scrollTo(tester, find.byKey(const Key('notif_documents')));
    await tester.tap(find.byKey(const Key('notif_documents')));
    await tester.pumpAndSettle();
    var updated =
        verify(() => mockUpdate.call(captureAny())).captured.last
            as NotificationPreferences;
    expect(updated.documents, isFalse);

    await scrollTo(tester, find.byKey(const Key('notif_messages')));
    await tester.tap(find.byKey(const Key('notif_messages')));
    await tester.pumpAndSettle();
    updated = verify(() => mockUpdate.call(captureAny())).captured.last
        as NotificationPreferences;
    expect(updated.messages, isTrue);

    await scrollTo(tester, find.byKey(const Key('notif_payments')));
    await tester.tap(find.byKey(const Key('notif_payments')));
    await tester.pumpAndSettle();
    updated = verify(() => mockUpdate.call(captureAny())).captured.last
        as NotificationPreferences;
    expect(updated.payments, isTrue);
  });

  testWidgets(
      'la bascule "heures calmes" est activée par défaut et se sauvegarde '
      'via le cubit', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final toggleFinder = find.byKey(const Key('notif_quiet_hours'));
    await scrollTo(tester, toggleFinder);
    final toggle = tester.widget<NubiaToggle>(toggleFinder);
    expect(toggle.value, isTrue);

    expect(find.text('Pas avant 8h ni après 21h'), findsOneWidget);
    expect(find.text('Sauf urgence de votre cabinet'), findsOneWidget);
    expect(find.byIcon(Icons.bedtime), findsOneWidget);

    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();

    final captured = verify(
      () => mockUpdate.call(captureAny()),
    ).captured;
    final updated = captured.last as NotificationPreferences;
    expect(updated.quietHours, isFalse);
  });

  testWidgets(
      'les sous-bascules sans champ API dédié sont désactivées et ne '
      'déclenchent aucune sauvegarde', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    for (final key in [
      'notif_appointments_reminder_48h',
      'notif_appointments_reminder_2h',
      'notif_pharmacy_order',
      'notif_quote',
    ]) {
      final finder = find.byKey(Key(key));
      await scrollTo(tester, finder);
      expect(finder, findsOneWidget, reason: key);
      final toggle = tester.widget<NubiaToggle>(finder);
      expect(toggle.onChanged, isNull, reason: key);
      expect(find.text('Bientôt disponible'), findsAtLeastNWidgets(1),
          reason: key);
    }

    verifyNever(() => mockUpdate.call(any()));
  });
}
