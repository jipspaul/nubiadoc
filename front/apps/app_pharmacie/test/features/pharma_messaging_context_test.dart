import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_pharmacie/features/pharma_messaging/pharma_messaging_bloc.dart';
import 'package:app_pharmacie/features/pharma_messaging/pharma_messaging_event.dart';
import 'package:app_pharmacie/features/pharma_messaging/pharma_messaging_page.dart';
import 'package:app_pharmacie/features/pharma_messaging/pharma_messaging_state.dart';

class MockPharmaMessagingBloc
    extends MockBloc<PharmaMessagingEvent, PharmaMessagingState>
    implements PharmaMessagingBloc {}

CabinetConversation conversation({
  String id = 'conv1',
  String patientName = 'Julie Martin',
  String? patientPhone = '0642180755',
  String? orderRef,
  String? orderStatusLabel,
}) =>
    CabinetConversation(
      id: id,
      patientId: 'pat_$id',
      patientName: patientName,
      patientPhone: patientPhone,
      unreadCount: 0,
      orderRef: orderRef,
      orderStatusLabel: orderStatusLabel,
    );

PharmacyOrder order(
  String id,
  PharmacyOrderStatus status, {
  DateTime? createdAt,
  int? lineCount = 3,
  String? orderRef,
}) =>
    PharmacyOrder(
      id: id,
      pharmacyId: 'ph1',
      patientDisplayName: 'Julie Martin',
      prescriptionId: 'rx_$id',
      status: status,
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: createdAt ?? DateTime.now(),
      lineCount: lineCount,
      orderRef: orderRef,
    );

void main() {
  late MockPharmaMessagingBloc bloc;

  setUp(() {
    bloc = MockPharmaMessagingBloc();
  });

  Future<void> pumpWide(
    WidgetTester tester,
    PharmaMessagingState state,
  ) async {
    when(() => bloc.state).thenReturn(state);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // La vue est un corps de ProShell : en production elle est montée sous le
    // Material d'un Scaffold. Le champ de saisie (TextField) et le bouton
    // d'envoi (IconButton) exigent cet ancêtre Material — on le fournit ici
    // via un Scaffold, comme les autres tests widget de la messagerie.
    await tester.pumpApp(
      Scaffold(
        body: BlocProvider<PharmaMessagingBloc>.value(
          value: bloc,
          child: const PharmaMessagingView(),
        ),
      ),
    );
  }

  group('Colonne contexte (#4926)', () {
    testWidgets(
        'fil ouvert sur poste large → colonne contexte avec les 3 sections + note',
        (tester) async {
      await pumpWide(
        tester,
        PharmaMessagingThreadLoaded(
          conversation: conversation(),
          messages: const [],
          patientOrders: [order('o1', PharmacyOrderStatus.ready)],
        ),
      );

      expect(find.byKey(const Key('pharma_messaging_context_panel')),
          findsOneWidget);
      expect(find.text('Patient'), findsOneWidget);
      expect(find.text('Commandes'), findsOneWidget);
      expect(find.text("Horaires aujourd'hui"), findsOneWidget);
      expect(find.byKey(const Key('pharma_messaging_ctx_note')),
          findsOneWidget);
    });

    testWidgets('section Patiente affiche le nom et le téléphone',
        (tester) async {
      await pumpWide(
        tester,
        PharmaMessagingThreadLoaded(
          conversation: conversation(
            patientName: 'Julie Martin',
            patientPhone: '0642180755',
          ),
          messages: const [],
        ),
      );

      expect(find.textContaining('Julie Martin'), findsWidgets);
      expect(find.textContaining('0642180755'), findsOneWidget);
    });

    testWidgets(
        'section Commandes liste les commandes du patient avec pastille de statut',
        (tester) async {
      await pumpWide(
        tester,
        PharmaMessagingThreadLoaded(
          conversation: conversation(),
          messages: const [],
          patientOrders: [
            order('o1', PharmacyOrderStatus.ready),
            order('o2', PharmacyOrderStatus.pickedUp),
          ],
        ),
      );

      expect(find.byKey(const Key('pharma_messaging_ctx_order_o1')),
          findsOneWidget);
      expect(find.byKey(const Key('pharma_messaging_ctx_order_o2')),
          findsOneWidget);
      expect(find.text('Prête'), findsOneWidget);
      expect(find.text('Retirée'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // badge total
    });

    testWidgets('aucune commande → « Aucune commande »', (tester) async {
      await pumpWide(
        tester,
        PharmaMessagingThreadLoaded(
          conversation: conversation(),
          messages: const [],
          patientOrders: const [],
        ),
      );

      expect(find.text('Aucune commande'), findsOneWidget);
    });

    testWidgets('pas de fil ouvert → pas de colonne contexte',
        (tester) async {
      await pumpWide(
        tester,
        PharmaMessagingConversationsLoaded([conversation()]),
      );

      expect(find.byKey(const Key('pharma_messaging_context_panel')),
          findsNothing);
    });
  });

  group('En-tête du fil — contexte commande (#8060)', () {
    testWidgets(
        'conversation rattachée à une commande connue → sous-titre + bouton « Ouvrir la commande »',
        (tester) async {
      await pumpWide(
        tester,
        PharmaMessagingThreadLoaded(
          conversation: conversation(
            orderRef: 'CMD-0542',
            orderStatusLabel: 'Reçue',
          ),
          messages: const [],
          patientOrders: [
            order('o1', PharmacyOrderStatus.received, orderRef: 'CMD-0542'),
          ],
        ),
      );

      expect(find.text('Commande CMD-0542 · Reçue'), findsOneWidget);
      expect(find.byKey(const Key('pharma_messaging_open_order_button')),
          findsOneWidget);
    });

    testWidgets(
        'conversation sans commande rattachée → ni sous-titre ni bouton',
        (tester) async {
      await pumpWide(
        tester,
        PharmaMessagingThreadLoaded(
          conversation: conversation(),
          messages: const [],
        ),
      );

      expect(find.textContaining('Commande '), findsNothing);
      expect(find.byKey(const Key('pharma_messaging_open_order_button')),
          findsNothing);
    });

    testWidgets(
        'commande rattachée absente de patientOrders → sous-titre affiché, bouton absent',
        (tester) async {
      await pumpWide(
        tester,
        PharmaMessagingThreadLoaded(
          conversation: conversation(
            orderRef: 'CMD-0542',
            orderStatusLabel: 'Reçue',
          ),
          messages: const [],
          patientOrders: const [],
        ),
      );

      expect(find.text('Commande CMD-0542 · Reçue'), findsOneWidget);
      expect(find.byKey(const Key('pharma_messaging_open_order_button')),
          findsNothing);
    });
  });
}
