import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/cabinet_messaging/cabinet_messaging_bloc.dart';
import 'package:app_practicien/features/cabinet_messaging/cabinet_messaging_event.dart';
import 'package:app_practicien/features/cabinet_messaging/cabinet_messaging_page.dart';
import 'package:app_practicien/features/cabinet_messaging/cabinet_messaging_state.dart';

/// Tests widget "Créer un RDV" depuis une conversation (#4160). Contrairement
/// à cabinet_messaging_test.dart (qui teste le bloc + un double minimal de la
/// page pour éviter GetIt), ces tests rendent la VRAIE `CabinetMessagingPage`
/// — le bouton et le sélecteur de créneau vivent dans `_ThreadView`, privé au
/// fichier de la page, donc injoignable sans passer par GetIt override.

class MockCabinetMessagingBloc
    extends MockBloc<CabinetMessagingEvent, CabinetMessagingState>
    implements CabinetMessagingBloc {}

class MockListBookableSlotsUseCase extends Mock
    implements ListBookableSlotsUseCase {}

final _conversation = CabinetConversation(
  id: 'conv-1',
  patientId: 'pat-1',
  patientName: 'Marie Dupont',
  unreadCount: 0,
);

final _slot = Slot(
  id: 'slot-1',
  cabinetId: 'cab-1',
  practitionerId: 'prac-1',
  startsAt: DateTime(2026, 8, 10, 9),
  endsAt: DateTime(2026, 8, 10, 9, 30),
  isAvailable: true,
);

/// Reproduit le formatage privé `AppointmentSlotPicker._slotLabel` pour
/// pouvoir cibler l'item du dropdown sans dupliquer le calcul du jour de
/// semaine à la main (fragile).
String _expectedSlotLabel(DateTime d) {
  const weekdays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
  const months = [
    'jan.', 'fév.', 'mar.', 'avr.', 'mai', 'juin', //
    'juil.', 'août', 'sep.', 'oct.', 'nov.', 'déc.',
  ];
  final h = '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
  return '${weekdays[d.weekday - 1]} ${d.day} ${months[d.month - 1]} – $h';
}

void main() {
  late MockCabinetMessagingBloc bloc;
  late MockListBookableSlotsUseCase mockSlots;

  setUp(() {
    bloc = MockCabinetMessagingBloc();
    mockSlots = MockListBookableSlotsUseCase();
    if (GetIt.instance.isRegistered<CabinetMessagingBloc>()) {
      GetIt.instance.unregister<CabinetMessagingBloc>();
    }
    GetIt.instance.registerFactory<CabinetMessagingBloc>(() => bloc);
    if (GetIt.instance.isRegistered<ListBookableSlotsUseCase>()) {
      GetIt.instance.unregister<ListBookableSlotsUseCase>();
    }
    GetIt.instance.registerFactory<ListBookableSlotsUseCase>(() => mockSlots);
  });

  tearDown(() => GetIt.instance.reset());

  testWidgets(
      'thread → "Créer un RDV" → choix du créneau → dispatch '
      'CabinetMessagingConvertToAppointmentRequested (#4160)', (tester) async {
    when(() => bloc.state).thenReturn(
      CabinetMessagingThreadLoaded(
          conversation: _conversation, messages: const []),
    );
    when(() => mockSlots()).thenAnswer((_) async => Right([_slot]));

    await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light, home: const Scaffold(body: CabinetMessagingPage())));
    await tester.pump();

    expect(
      find.byKey(const Key('create_appointment_from_conversation')),
      findsOneWidget,
    );
    await tester
        .tap(find.byKey(const Key('create_appointment_from_conversation')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('appointment_slot_picker')), findsOneWidget);
    await tester.tap(find.byKey(const Key('appointment_slot_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_expectedSlotLabel(_slot.startsAt)).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('appointment_slot_picker_confirm')));
    await tester.pumpAndSettle();

    verify(() => bloc.add(const CabinetMessagingConvertToAppointmentRequested(
          conversationId: 'conv-1',
          slotId: 'slot-1',
        ))).called(1);
  });

  testWidgets(
      'converting: true — bouton "Créer un RDV" remplacé par un indicateur '
      'de chargement', (tester) async {
    when(() => bloc.state).thenReturn(
      CabinetMessagingThreadLoaded(
        conversation: _conversation,
        messages: const [],
        converting: true,
      ),
    );
    await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light, home: const Scaffold(body: CabinetMessagingPage())));
    await tester.pump();

    expect(
      find.byKey(const Key('create_appointment_from_conversation')),
      findsNothing,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('conversionError — bannière d\'erreur affichée dans le thread',
      (tester) async {
    when(() => bloc.state).thenReturn(
      CabinetMessagingThreadLoaded(
        conversation: _conversation,
        messages: const [],
        conversionError:
            'Ce créneau vient d\'être réservé, choisissez-en un autre.',
      ),
    );
    await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light, home: const Scaffold(body: CabinetMessagingPage())));
    await tester.pump();

    expect(find.byKey(const Key('conversion_error_banner')), findsOneWidget);
    expect(
      find.text('Ce créneau vient d\'être réservé, choisissez-en un autre.'),
      findsOneWidget,
    );
    // Le bouton reste disponible pour réessayer (pas de conversion en cours).
    expect(
      find.byKey(const Key('create_appointment_from_conversation')),
      findsOneWidget,
    );
  });
}
