import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/notifications/notifications_bloc.dart';
import 'package:app_patient/features/notifications/notifications_event.dart';
import 'package:app_patient/features/notifications/notifications_page.dart';
import 'package:app_patient/features/notifications/notifications_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockNotificationsBloc
    extends MockBloc<NotificationsEvent, NotificationsState>
    implements NotificationsBloc {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

AppNotification _notif(String id) => AppNotification(
      id: id,
      type: NotificationType.appointment,
      title: 'Titre $id',
      body: 'Corps $id',
      read: false,
      createdAt: DateTime(2026, 6, 21),
    );

AppNotification _typedNotif(String id, NotificationType type) => AppNotification(
      id: id,
      type: type,
      title: 'Titre $id',
      body: 'Corps $id',
      read: false,
      createdAt: DateTime(2026, 6, 21),
    );

AppNotification _actionableNotif(
  String id,
  NotificationType type, {
  required String deepLink,
  String? kind,
  String? status,
}) =>
    AppNotification(
      id: id,
      type: type,
      title: 'Titre $id',
      body: 'Corps $id',
      read: false,
      createdAt: DateTime(2026, 6, 21),
      deepLink: deepLink,
      kind: kind,
      status: status,
    );

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(NotificationsBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<NotificationsBloc>.value(
        value: bloc,
        child: const Scaffold(body: NotificationsPage()),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(const NotificationMarkReadRequested('_'));
    registerFallbackValue(const NotificationsLoadRequested());
  });

  group('NotificationsPage — état Initial', () {
    testWidgets('affiche le spinner en état Initial', (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(const NotificationsInitial());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notifications_loading')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('NotificationsPage — état Loading', () {
    testWidgets('affiche le spinner en état Loading', (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(const NotificationsLoading());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notifications_loading')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('NotificationsPage — état Error', () {
    testWidgets('affiche NubiaErrorWidget en état Error', (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state)
          .thenReturn(const NotificationsError('Erreur de chargement.'));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notifications_error')), findsOneWidget);
      expect(find.byType(NubiaErrorWidget), findsOneWidget);
      expect(find.text('Erreur de chargement.'), findsOneWidget);
    });

    testWidgets('bouton Réessayer dispatche NotificationsLoadRequested',
        (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state)
          .thenReturn(const NotificationsError('Erreur de chargement.'));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      await tester.tap(find.text('Réessayer'));
      await tester.pump();

      verify(() => bloc.add(const NotificationsLoadRequested())).called(1);
    });
  });

  group('NotificationsPage — état Empty', () {
    testWidgets('affiche NubiaEmptyState en état NotificationsEmpty',
        (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(const NotificationsEmpty());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notifications_empty')), findsOneWidget);
      expect(find.byType(NubiaEmptyState), findsOneWidget);
    });

    testWidgets('affiche NubiaEmptyState quand Loaded([]) est émis',
        (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(const NotificationsLoaded([]));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notifications_empty')), findsOneWidget);
      expect(find.byType(NubiaEmptyState), findsOneWidget);
    });
  });

  group('NotificationsPage — Loaded(2 notifs)', () {
    testWidgets('affiche 2 ListTile quand 2 notifications sont chargées',
        (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state)
          .thenReturn(NotificationsLoaded([_notif('1'), _notif('2')]));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notif_1')), findsOneWidget);
      expect(find.byKey(const Key('notif_2')), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(2));
    });
  });

  group('NotificationsPage — horodatage (#5305)', () {
    testWidgets(
        "une notification du jour affiche l'heure locale HH:mm en brand700 "
        'gras quand non lue', (tester) async {
      final bloc = MockNotificationsBloc();
      final now = DateTime.now();
      final createdAt = DateTime(now.year, now.month, now.day, 9, 4);
      when(() => bloc.state).thenReturn(
        NotificationsLoaded([
          AppNotification(
            id: 'today',
            type: NotificationType.appointment,
            title: 'Titre today',
            body: 'Corps today',
            read: false,
            createdAt: createdAt,
          ),
        ]),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.text('09:04'), findsOneWidget);
      final style = tester.widget<Text>(find.text('09:04')).style;
      expect(style?.color, NubiaColors.brand700);
      expect(style?.fontWeight, FontWeight.bold);
    });

    testWidgets(
        'une notification antérieure lue affiche "<jour> <mois abrégé>" en '
        'n500', (tester) async {
      const months = [
        'jan', 'fév', 'mar', 'avr', 'mai', 'jun',
        'jul', 'aoû', 'sep', 'oct', 'nov', 'déc', //
      ];
      final createdAt = DateTime.now().subtract(const Duration(days: 13));
      final expected = '${createdAt.day} ${months[createdAt.month - 1]}';

      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(
        NotificationsLoaded([
          AppNotification(
            id: 'older',
            type: NotificationType.appointment,
            title: 'Titre older',
            body: 'Corps older',
            read: true,
            createdAt: createdAt,
          ),
        ]),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.text(expected), findsOneWidget);
      final style = tester.widget<Text>(find.text(expected)).style;
      expect(style?.color, NubiaColors.n500);
      expect(style?.fontWeight, FontWeight.normal);
    });
  });

  group('NotificationsPage — tap → mark-as-read', () {
    testWidgets(
        'un tap sur une notification dispatche NotificationMarkReadRequested',
        (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state)
          .thenReturn(NotificationsLoaded([_notif('1'), _notif('2')]));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      await tester.tap(find.byKey(const Key('notif_1')));
      await tester.pump();

      verify(() => bloc.add(const NotificationMarkReadRequested('1')))
          .called(1);
    });
  });

  group('NotificationsPage — tap corps vs bouton d\'action', () {
    testWidgets(
        'le tap sur le corps d\'une notification actionnable marque comme '
        'lu SANS naviguer', (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(
        NotificationsLoaded([
          _actionableNotif('1', NotificationType.appointment,
              deepLink: '/appointments/42'),
        ]),
      );

      final router = GoRouter(
        initialLocation: '/notifications',
        routes: [
          GoRoute(
            path: '/notifications',
            builder: (context, __) => BlocProvider<NotificationsBloc>.value(
              value: bloc,
              child: const Scaffold(body: NotificationsPage()),
            ),
          ),
          GoRoute(
            path: '/mes-rdv',
            builder: (_, __) => const Scaffold(
              key: Key('mes_rdv_page'),
              body: SizedBox(),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Corps 1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mes_rdv_page')), findsNothing);
      expect(find.byType(NotificationsPage), findsOneWidget);
      verify(() => bloc.add(const NotificationMarkReadRequested('1')))
          .called(1);
    });
  });

  group('NotificationsPage — bouton d\'action', () {
    testWidgets(
        'une notification sans deepLink n\'affiche aucun bouton d\'action',
        (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(NotificationsLoaded([_notif('1')]));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notif_action_1')), findsNothing);
    });

    testWidgets(
        'une notification pharmacie prête (other, status=ready) affiche un '
        'bouton primaire « Afficher mon code »', (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(
        NotificationsLoaded([
          _actionableNotif('1', NotificationType.other,
              deepLink: '/pharmacy/orders/42',
              kind: 'order_status_changed',
              status: 'ready'),
        ]),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notif_action_1')), findsOneWidget);
      expect(find.text('Afficher mon code'), findsOneWidget);
      expect(find.byIcon(Icons.qr_code_2), findsOneWidget);
      final button =
          tester.widget<NubiaButton>(find.byKey(const Key('notif_action_1')));
      expect(button.variant, NubiaButtonVariant.primary);
    });

    // Régression #6610 : les 3 statuts d'une commande partageaient tous le
    // même libellé « Afficher mon code », y compris une commande pas encore
    // prête ou déjà retirée — menant vers un écran sans le moindre code.
    testWidgets(
        'une commande en préparation (other, status=preparing) affiche '
        '« Suivre ma commande », pas « Afficher mon code »', (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(
        NotificationsLoaded([
          _actionableNotif('1', NotificationType.other,
              deepLink: '/pharmacy/orders/42',
              kind: 'order_status_changed',
              status: 'preparing'),
        ]),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.text('Suivre ma commande'), findsOneWidget);
      expect(find.text('Afficher mon code'), findsNothing);
      final button =
          tester.widget<NubiaButton>(find.byKey(const Key('notif_action_1')));
      expect(button.variant, NubiaButtonVariant.secondary);
    });

    testWidgets(
        'une commande déjà retirée (other, status=picked_up) affiche '
        '« Voir la commande », pas « Afficher mon code »', (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(
        NotificationsLoaded([
          _actionableNotif('1', NotificationType.other,
              deepLink: '/pharmacy/orders/42',
              kind: 'order_status_changed',
              status: 'picked_up'),
        ]),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.text('Voir la commande'), findsOneWidget);
      expect(find.text('Afficher mon code'), findsNothing);
      final button =
          tester.widget<NubiaButton>(find.byKey(const Key('notif_action_1')));
      expect(button.variant, NubiaButtonVariant.secondary);
    });

    testWidgets(
        'une notification message affiche un bouton secondaire « Répondre »',
        (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(
        NotificationsLoaded([
          _actionableNotif('1', NotificationType.message,
              deepLink: '/messaging?conversationId=7'),
        ]),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.text('Répondre'), findsOneWidget);
      expect(find.byIcon(Icons.reply), findsOneWidget);
      final button =
          tester.widget<NubiaButton>(find.byKey(const Key('notif_action_1')));
      expect(button.variant, NubiaButtonVariant.secondary);
    });

    testWidgets(
        'un devis d\'officine « À signer » (payment/pharmacy_quote_sent) '
        'affiche « Voir le devis », pas « Voir la facture » (#6580 — jusqu\'ici '
        'aucun deep_link n\'était dérivé, donc aucun bouton du tout)',
        (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(
        NotificationsLoaded([
          _actionableNotif('1', NotificationType.payment,
              deepLink: '/pharmacy/quotes', kind: 'pharmacy_quote_sent'),
        ]),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notif_action_1')), findsOneWidget);
      expect(find.text('Voir le devis'), findsOneWidget);
      expect(find.text('Voir la facture'), findsNothing);
      expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    });

    testWidgets(
        'le tap sur le bouton (pas le corps) navigue vers la route résolue '
        'et marque la notification comme lue', (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(
        NotificationsLoaded([
          _actionableNotif('1', NotificationType.appointment,
              deepLink: '/appointments/42'),
        ]),
      );

      final router = GoRouter(
        initialLocation: '/notifications',
        routes: [
          GoRoute(
            path: '/notifications',
            builder: (context, __) => BlocProvider<NotificationsBloc>.value(
              value: bloc,
              child: const Scaffold(body: NotificationsPage()),
            ),
          ),
          GoRoute(
            path: '/mes-rdv',
            builder: (_, __) => const Scaffold(
              key: Key('mes_rdv_page'),
              body: SizedBox(),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notif_action_1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mes_rdv_page')), findsOneWidget);
      verify(() => bloc.add(const NotificationMarkReadRequested('1')))
          .called(1);
    });
  });

  group('NotificationsAppBar', () {
    Widget wrapAppBar(NotificationsBloc bloc) => MaterialApp(
          home: BlocProvider<NotificationsBloc>.value(
            value: bloc,
            child: const Scaffold(appBar: NotificationsAppBar()),
          ),
        );

    testWidgets('affiche le sous-titre "N non lues" et l\'action quand '
        'des notifications ne sont pas lues', (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state)
          .thenReturn(NotificationsLoaded([_notif('1'), _notif('2')]));

      await tester.pumpWidget(wrapAppBar(bloc));
      await tester.pump();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('2 non lues'), findsOneWidget);
      expect(find.text('Tout marquer lu'), findsOneWidget);
      expect(find.byIcon(Icons.done_all), findsOneWidget);
    });

    testWidgets('accorde le sous-titre au singulier pour une seule '
        'notification non lue', (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(NotificationsLoaded([_notif('1')]));

      await tester.pumpWidget(wrapAppBar(bloc));
      await tester.pump();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('1 non lue'), findsOneWidget);
    });

    testWidgets('masque l\'action quand il n\'y a aucune notification non '
        'lue', (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(const NotificationsLoaded([]));

      await tester.pumpWidget(wrapAppBar(bloc));
      await tester.pump();

      expect(find.text('0 non lues'), findsOneWidget);
      expect(find.text('Tout marquer lu'), findsNothing);
    });

    testWidgets(
        'un tap sur l\'action dispatche NotificationMarkAllReadRequested',
        (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state)
          .thenReturn(NotificationsLoaded([_notif('1'), _notif('2')]));

      await tester.pumpWidget(wrapAppBar(bloc));
      await tester.pump();

      await tester.tap(find.text('Tout marquer lu'));
      await tester.pump();

      verify(() => bloc.add(const NotificationMarkAllReadRequested()))
          .called(1);
    });
  });

  group('NotificationsPage — regroupement par jour', () {
    testWidgets(
        "affiche l'en-tête Aujourd'hui pour une notification du jour et "
        "Cette semaine pour une notification plus ancienne", (tester) async {
      final bloc = MockNotificationsBloc();
      final now = DateTime.now();
      when(() => bloc.state).thenReturn(
        NotificationsLoaded([
          AppNotification(
            id: 'today',
            type: NotificationType.appointment,
            title: 'Titre today',
            body: 'Corps today',
            read: false,
            createdAt: now,
          ),
          AppNotification(
            id: 'older',
            type: NotificationType.appointment,
            title: 'Titre older',
            body: 'Corps older',
            read: false,
            createdAt: now.subtract(const Duration(days: 2)),
          ),
        ]),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notif_group_today')), findsOneWidget);
      expect(find.byKey(const Key('notif_group_week')), findsOneWidget);
      expect(find.text("AUJOURD'HUI"), findsOneWidget);
      expect(find.text('CETTE SEMAINE'), findsOneWidget);
      expect(find.byKey(const Key('notif_today')), findsOneWidget);
      expect(find.byKey(const Key('notif_older')), findsOneWidget);
    });

    testWidgets(
        "n'affiche aucun en-tête Cette semaine quand toutes les "
        "notifications sont du jour", (tester) async {
      final bloc = MockNotificationsBloc();
      final now = DateTime.now();
      when(() => bloc.state).thenReturn(
        NotificationsLoaded([
          AppNotification(
            id: 'today',
            type: NotificationType.appointment,
            title: 'Titre today',
            body: 'Corps today',
            read: false,
            createdAt: now,
          ),
        ]),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notif_group_today')), findsOneWidget);
      expect(find.byKey(const Key('notif_group_week')), findsNothing);
    });
  });

  group('NotificationsPage — facettes', () {
    List<AppNotification> fixtures() => [
          _typedNotif('1', NotificationType.appointment),
          _typedNotif('2', NotificationType.appointment),
          _typedNotif('3', NotificationType.document),
          _typedNotif('4', NotificationType.document),
          _typedNotif('5', NotificationType.payment),
          _typedNotif('6', NotificationType.message),
        ];

    testWidgets('affiche les 4 facettes avec leur compteur client',
        (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(NotificationsLoaded(fixtures()));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notif_filter_all')), findsOneWidget);
      expect(
          find.byKey(const Key('notif_filter_appointment')), findsOneWidget);
      expect(find.byKey(const Key('notif_filter_document')), findsOneWidget);
      expect(find.byKey(const Key('notif_filter_payment')), findsOneWidget);

      expect(
        find.descendant(
          of: find.byKey(const Key('notif_filter_all')),
          matching: find.text('6'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('notif_filter_appointment')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('notif_filter_document')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('notif_filter_payment')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'sélectionner une facette ne montre que les notifications de ce '
        'type, sans appel bloc supplémentaire', (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(NotificationsLoaded(fixtures()));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      await tester.tap(find.byKey(const Key('notif_filter_document')));
      await tester.pump();

      expect(find.byKey(const Key('notif_1')), findsNothing);
      expect(find.byKey(const Key('notif_3')), findsOneWidget);
      expect(find.byKey(const Key('notif_4')), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(2));

      await tester.tap(find.byKey(const Key('notif_filter_all')));
      await tester.pump();

      expect(find.byType(ListTile), findsNWidgets(6));
    });
  });
}
