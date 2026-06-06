import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/domain/entities/notification_preferences.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_settings_cubit.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_settings_state.dart';
import 'package:nubia_patient/presentation/features/notifications/pages/notification_settings_screen.dart';
import 'package:nubia_patient/presentation/features/notifications/widgets/notification_settings_tile.dart';

class MockNotificationSettingsCubit
    extends MockCubit<NotificationSettingsState>
    implements NotificationSettingsCubit {}

const _prefs = NotificationPreferences(
  pushEnabled: true,
  emailEnabled: false,
  smsEnabled: true,
  appointments: true,
  documents: false,
  messages: true,
  payments: false,
  prevention: true,
);

Widget _wrap(NotificationSettingsCubit cubit) {
  return MaterialApp(
    home: BlocProvider<NotificationSettingsCubit>.value(
      value: cubit,
      child: const NotificationSettingsScreen(),
    ),
  );
}

void main() {
  late MockNotificationSettingsCubit cubit;

  setUp(() {
    cubit = MockNotificationSettingsCubit();
  });

  tearDown(() => cubit.close());

  testWidgets(
      'affiche un indicateur de chargement en état Loading',
      (tester) async {
    when(() => cubit.state)
        .thenReturn(const NotificationSettingsLoading());

    await tester.pumpWidget(_wrap(cubit));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('affiche un message d\'erreur en état Error', (tester) async {
    when(() => cubit.state)
        .thenReturn(const NotificationSettingsError('Erreur réseau.'));

    await tester.pumpWidget(_wrap(cubit));

    expect(find.text('Erreur réseau.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  testWidgets('affiche les toggles de canaux et de types en état Loaded',
      (tester) async {
    when(() => cubit.state)
        .thenReturn(const NotificationSettingsLoaded(_prefs));

    await tester.pumpWidget(_wrap(cubit));
    // Scroll to ensure all items are laid out (SingleChildScrollView + Column).
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -500));
    await tester.pump();

    // 3 channel tiles + 5 type tiles = 8 total (skipOffstage to count all)
    expect(
      find.byType(NotificationSettingsTile, skipOffstage: false),
      findsNWidgets(8),
    );
    expect(find.text('Notifications push', skipOffstage: false),
        findsOneWidget);
    expect(find.text('E-mail', skipOffstage: false), findsOneWidget);
    expect(find.text('SMS', skipOffstage: false), findsOneWidget);
    expect(find.text('Rendez-vous', skipOffstage: false), findsOneWidget);
    expect(find.text('Documents', skipOffstage: false), findsOneWidget);
    expect(find.text('Messages', skipOffstage: false), findsOneWidget);
    expect(find.text('Paiements', skipOffstage: false), findsOneWidget);
    expect(find.text('Prévention', skipOffstage: false), findsOneWidget);
  });

  testWidgets('appelle toggle(appointments:) quand on tape sur le switch RDV',
      (tester) async {
    when(() => cubit.state)
        .thenReturn(const NotificationSettingsLoaded(_prefs));
    when(() => cubit.toggle(appointments: false)).thenAnswer((_) async {});

    await tester.pumpWidget(_wrap(cubit));

    // The Rendez-vous tile has its switch ON; tap to disable.
    final rdvSwitch = find.descendant(
      of: find.widgetWithText(SwitchListTile, 'Rendez-vous'),
      matching: find.byType(Switch),
    );
    await tester.tap(rdvSwitch);
    await tester.pump();

    verify(() => cubit.toggle(appointments: false)).called(1);
  });

  testWidgets('appelle toggle(pushEnabled:) quand on tape sur le switch push',
      (tester) async {
    when(() => cubit.state)
        .thenReturn(const NotificationSettingsLoaded(_prefs));
    when(() => cubit.toggle(pushEnabled: false)).thenAnswer((_) async {});

    await tester.pumpWidget(_wrap(cubit));

    // Push switch is ON; tap to disable.
    final pushSwitch = find.descendant(
      of: find.widgetWithText(SwitchListTile, 'Notifications push'),
      matching: find.byType(Switch),
    );
    await tester.tap(pushSwitch);
    await tester.pump();

    verify(() => cubit.toggle(pushEnabled: false)).called(1);
  });
}
