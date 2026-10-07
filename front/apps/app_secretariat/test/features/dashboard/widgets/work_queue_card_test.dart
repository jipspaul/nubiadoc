import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/dashboard/expiring_quotes_summary_cubit.dart';
import 'package:app_secretariat/features/dashboard/patient_messages_summary_cubit.dart';
import 'package:app_secretariat/features/dashboard/widgets/work_queue_card.dart';

class _MockPatientMessagesSummaryCubit
    extends MockCubit<PatientMessagesSummaryState>
    implements PatientMessagesSummaryCubit {}

class _MockExpiringQuotesSummaryCubit
    extends MockCubit<ExpiringQuotesSummaryState>
    implements ExpiringQuotesSummaryCubit {}

AgendaEntry _pendingEntry(
  String id, {
  required String patientName,
  required DateTime startsAt,
}) =>
    AgendaEntry(
      id: id,
      cabinetId: 'cab',
      practitionerId: 'prac',
      practitionerName: 'Dr T',
      startsAt: startsAt,
      endsAt: startsAt.add(const Duration(minutes: 30)),
      patientName: patientName,
      isFree: false,
      status: 'requested',
    );

CabinetQuote _quote(
  String id, {
  required String patientName,
  required DateTime expiresAt,
}) =>
    CabinetQuote(
      id: id,
      quoteRef: id,
      cabinetId: 'cab',
      patientId: 'p-$id',
      patientName: patientName,
      totalCents: 10000,
      patientShareCents: 5000,
      status: CabinetQuoteStatus.sent,
      createdAt: DateTime(2026, 1, 1),
      expiresAt: expiresAt,
    );

Widget _wrap(
  PatientMessagesSummaryCubit messagesCubit,
  ExpiringQuotesSummaryCubit quotesCubit, {
  int waitingCount = 0,
  Duration? oldestWaitingRequestAge,
  List<AgendaEntry> pendingAppointmentsToday = const [],
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<PatientMessagesSummaryCubit>.value(
                value: messagesCubit,
              ),
              BlocProvider<ExpiringQuotesSummaryCubit>.value(
                value: quotesCubit,
              ),
            ],
            child: WorkQueueCard(
              waitingCount: waitingCount,
              oldestWaitingRequestAge: oldestWaitingRequestAge,
              pendingAppointmentsToday: pendingAppointmentsToday,
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/messages',
        builder: (context, state) => Scaffold(
          body: Text('Messagerie extra=${state.extra}'),
        ),
      ),
      GoRoute(
        path: '/liste-attente',
        builder: (context, state) =>
            const Scaffold(body: Text('Liste d\'attente')),
      ),
      GoRoute(
        path: '/devis',
        builder: (context, state) => Scaffold(
          body: Text('Devis extra=${state.extra}'),
        ),
      ),
      GoRoute(
        path: '/agenda',
        builder: (context, state) => Scaffold(
          body: Text('Agenda extra=${state.extra}'),
        ),
      ),
    ],
  );
  return MaterialApp.router(
    theme: NubiaTheme.light,
    routerConfig: router,
  );
}

void main() {
  group('WorkQueueCard', () {
    late _MockPatientMessagesSummaryCubit cubit;
    late _MockExpiringQuotesSummaryCubit quotesCubit;

    setUp(() {
      cubit = _MockPatientMessagesSummaryCubit();
      quotesCubit = _MockExpiringQuotesSummaryCubit();
      when(() => quotesCubit.state)
          .thenReturn(const ExpiringQuotesSummaryLoaded(quotes: []));
    });

    testWidgets('affiche le squelette de chargement', (tester) async {
      when(() => cubit.state).thenReturn(const PatientMessagesSummaryLoading());
      await tester.pumpWidget(_wrap(cubit, quotesCubit));
      expect(find.byKey(const Key('work_queue_card_loading')), findsOneWidget);
    });

    testWidgets('affiche une erreur', (tester) async {
      when(() => cubit.state).thenReturn(
          const PatientMessagesSummaryError(message: 'Erreur test'));
      await tester.pumpWidget(_wrap(cubit, quotesCubit));
      expect(find.byKey(const Key('work_queue_card_error')), findsOneWidget);
      expect(find.text('Erreur test'), findsOneWidget);
    });

    testWidgets(
        '#5379/#6246 : titre = messages non lus, sous-titre = urgent, '
        'Ouvrir → /messages ciblé sur la conversation urgente',
        (tester) async {
      when(() => cubit.state).thenReturn(
        const PatientMessagesSummaryLoaded(
          unreadCount: 4,
          urgentUnreadCount: 1,
          urgentPatientName: 'Ahmed Belkacem',
          urgentConversationId: 'conv-urgent',
        ),
      );
      await tester.pumpWidget(_wrap(cubit, quotesCubit));

      expect(find.byKey(const Key('work_queue_card')), findsOneWidget);
      expect(find.text('À traiter maintenant'), findsOneWidget);
      expect(find.text('4 messages patients non lus'), findsOneWidget);
      expect(
        find.text('Dont 1 marqué urgent par Ahmed Belkacem'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.chat_bubble), findsOneWidget);

      final openMessagesButton = find.descendant(
        of: find.byKey(const Key('work_queue_unread_messages_row')),
        matching: find.text('Ouvrir'),
      );
      expect(openMessagesButton, findsOneWidget);

      await tester.tap(openMessagesButton);
      await tester.pumpAndSettle();
      expect(find.text('Messagerie extra=conv-urgent'), findsOneWidget);
    });

    testWidgets(
        '#5378 : titre = demandes de créneau sans réponse, sous-titre = '
        'ancienneté, Ouvrir → /liste-attente', (tester) async {
      when(() => cubit.state).thenReturn(
        const PatientMessagesSummaryLoaded(
          unreadCount: 4,
          urgentUnreadCount: 0,
        ),
      );
      await tester.pumpWidget(
        _wrap(cubit, quotesCubit,
            waitingCount: 3, oldestWaitingRequestAge: const Duration(days: 5)),
      );

      expect(
        find.byKey(const Key('work_queue_waiting_list_row')),
        findsOneWidget,
      );
      expect(find.text('3 demandes de créneau sans réponse'), findsOneWidget);
      expect(
        find.text('La plus ancienne attend depuis 5 jours'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);

      await tester.ensureVisible(
        find.descendant(
          of: find.byKey(const Key('work_queue_waiting_list_row')),
          matching: find.text('Ouvrir'),
        ),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('work_queue_waiting_list_row')),
          matching: find.text('Ouvrir'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Liste d\'attente'), findsOneWidget);
    });

    testWidgets(
        '#6926 : ancienneté sous l\'heure → "moins d\'une heure", jamais '
        '"0 jours"', (tester) async {
      when(() => cubit.state).thenReturn(
        const PatientMessagesSummaryLoaded(
          unreadCount: 4,
          urgentUnreadCount: 0,
        ),
      );
      await tester.pumpWidget(
        _wrap(cubit, quotesCubit,
            waitingCount: 1, oldestWaitingRequestAge: const Duration(minutes: 3)),
      );

      expect(
        find.text('La plus ancienne attend depuis moins d\'une heure'),
        findsOneWidget,
      );
      expect(find.textContaining('0 jour'), findsNothing);
    });

    testWidgets(
        '#6926 : ancienneté en heures sous la journée → accord en heures',
        (tester) async {
      when(() => cubit.state).thenReturn(
        const PatientMessagesSummaryLoaded(
          unreadCount: 4,
          urgentUnreadCount: 0,
        ),
      );
      await tester.pumpWidget(
        _wrap(cubit, quotesCubit,
            waitingCount: 1, oldestWaitingRequestAge: const Duration(hours: 3)),
      );

      expect(
        find.text('La plus ancienne attend depuis 3 heures'),
        findsOneWidget,
      );
    });

    testWidgets(
        '#5375/#5378 : liste d\'attente vide → ligne masquée (pas de "0 '
        'demandes")', (tester) async {
      when(() => cubit.state).thenReturn(
        const PatientMessagesSummaryLoaded(
          unreadCount: 2,
          urgentUnreadCount: 0,
        ),
      );
      await tester.pumpWidget(_wrap(cubit, quotesCubit, waitingCount: 0));

      expect(
        find.byKey(const Key('work_queue_waiting_list_row')),
        findsNothing,
      );
      expect(find.textContaining('demandes de créneau'), findsNothing);
    });

    testWidgets('#5375/#5379 : aucun message non lu → ligne masquée',
        (tester) async {
      when(() => cubit.state).thenReturn(
        const PatientMessagesSummaryLoaded(
          unreadCount: 0,
          urgentUnreadCount: 0,
        ),
      );
      await tester.pumpWidget(_wrap(cubit, quotesCubit, waitingCount: 3));

      expect(
        find.byKey(const Key('work_queue_unread_messages_row')),
        findsNothing,
      );
      expect(find.textContaining('messages patients non lus'), findsNothing);
      expect(find.textContaining('marqué urgent'), findsNothing);
    });

    testWidgets(
        '#5375 : aucun sujet dans aucune section → état vide rassurant, '
        'badge « 0 sujets »', (tester) async {
      when(() => cubit.state).thenReturn(
        const PatientMessagesSummaryLoaded(
          unreadCount: 0,
          urgentUnreadCount: 0,
        ),
      );
      await tester.pumpWidget(_wrap(cubit, quotesCubit, waitingCount: 0));

      expect(find.byKey(const Key('work_queue_card_empty')), findsOneWidget);
      expect(find.text('Rien à traiter pour le moment'), findsOneWidget);
      expect(find.text('0 sujets'), findsOneWidget);
      expect(find.byKey(const Key('work_queue_waiting_list_row')), findsNothing);
      expect(
        find.byKey(const Key('work_queue_unread_messages_row')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('work_queue_expiring_quotes_row')),
        findsNothing,
      );
    });

    testWidgets('#5375 : badge « N sujets » compte les lignes présentes',
        (tester) async {
      when(() => cubit.state).thenReturn(
        const PatientMessagesSummaryLoaded(
          unreadCount: 4,
          urgentUnreadCount: 1,
          urgentPatientName: 'Ahmed Belkacem',
        ),
      );
      when(() => quotesCubit.state).thenReturn(
        ExpiringQuotesSummaryLoaded(
          quotes: [
            _quote('q1',
                patientName: 'Julie Martin', expiresAt: DateTime(2026, 8, 13)),
          ],
        ),
      );
      await tester.pumpWidget(
        _wrap(
          cubit,
          quotesCubit,
          waitingCount: 3,
          oldestWaitingRequestAge: const Duration(days: 5),
          pendingAppointmentsToday: [
            _pendingEntry(
              'rdv1',
              patientName: 'Sophie Roux',
              startsAt: DateTime(2026, 8, 16, 15, 30),
            ),
          ],
        ),
      );

      // 1 RDV non confirmé + demandes de créneau + devis + messages = 4.
      expect(find.text('4 sujets'), findsOneWidget);
    });

    testWidgets(
        '#5377/#6246 : titre = devis qui expirent, sous-titre = patients '
        '(JJ/MM), Relancer → /devis ciblé sur le devis le plus urgent',
        (tester) async {
      when(() => cubit.state).thenReturn(
        const PatientMessagesSummaryLoaded(
          unreadCount: 0,
          urgentUnreadCount: 0,
        ),
      );
      when(() => quotesCubit.state).thenReturn(
        ExpiringQuotesSummaryLoaded(
          quotes: [
            _quote('q1',
                patientName: 'Julie Martin', expiresAt: DateTime(2026, 8, 13)),
            _quote('q2',
                patientName: 'Théo Girard', expiresAt: DateTime(2026, 8, 16)),
            _quote('q3',
                patientName: 'Nina Lopez', expiresAt: DateTime(2026, 8, 17)),
          ],
        ),
      );
      await tester.pumpWidget(_wrap(cubit, quotesCubit));

      expect(
        find.byKey(const Key('work_queue_expiring_quotes_row')),
        findsOneWidget,
      );
      expect(find.text('3 devis expirent cette semaine'), findsOneWidget);
      // #7964 : au plus 2 patients nommés + le reste résumé en compte, pour
      // rester lisible dans la largeur bornée de la ligne.
      expect(
        find.text('Julie Martin (13/08), Théo Girard (16/08) et 1 autre'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.description), findsOneWidget);

      final relanceButton = find.descendant(
        of: find.byKey(const Key('work_queue_expiring_quotes_row')),
        matching: find.text('Relancer'),
      );
      expect(relanceButton, findsOneWidget);

      await tester.ensureVisible(relanceButton);
      await tester.tap(relanceButton);
      await tester.pumpAndSettle();
      // q1 expire le premier (13/08) : c'est le devis le plus urgent, en
      // tête de la liste triée par expiration croissante.
      expect(find.text('Devis extra=q1'), findsOneWidget);
    });

    testWidgets(
        '#7964 : sous-titre devis expirants borné même avec beaucoup '
        "d'entrées et des doublons patient/date", (tester) async {
      when(() => cubit.state).thenReturn(
        const PatientMessagesSummaryLoaded(
          unreadCount: 0,
          urgentUnreadCount: 0,
        ),
      );
      when(() => quotesCubit.state).thenReturn(
        ExpiringQuotesSummaryLoaded(
          quotes: [
            for (var i = 0; i < 9; i++)
              _quote('q-dup-$i',
                  patientName: 'Marc Dubois', expiresAt: DateTime(2026, 10, 5)),
            _quote('q-other',
                patientName: 'Camille Rousseau',
                expiresAt: DateTime(2026, 10, 6)),
            for (var i = 0; i < 21; i++)
              _quote('q-rest-$i',
                  patientName: 'Karim Saïdi', expiresAt: DateTime(2026, 10, 8)),
          ],
        ),
      );
      await tester.pumpWidget(_wrap(cubit, quotesCubit));

      expect(find.text('31 devis expirent cette semaine'), findsOneWidget);
      // Bornée à 2 patients distincts + le reste en compte, pas 31 entrées
      // concaténées tronquées à l'ellipse.
      expect(
        find.text('Marc Dubois (05/10), Camille Rousseau (06/10) et 29 autres'),
        findsOneWidget,
      );
    });

    testWidgets(
        '#5376/#6246 : titre = RDV non confirmé, bouton primaire Appeler → '
        '/agenda ciblé sur le RDV', (tester) async {
      when(() => cubit.state).thenReturn(
        const PatientMessagesSummaryLoaded(
          unreadCount: 0,
          urgentUnreadCount: 0,
        ),
      );
      await tester.pumpWidget(
        _wrap(
          cubit,
          quotesCubit,
          pendingAppointmentsToday: [
            _pendingEntry(
              'rdv1',
              patientName: 'Sophie Roux',
              startsAt: DateTime(2026, 8, 16, 15, 30),
            ),
          ],
        ),
      );

      expect(
        find.byKey(const Key('work_queue_pending_appointment_row_rdv1')),
        findsOneWidget,
      );
      expect(
        find.text("15:30 — Sophie Roux n'a pas confirmé son RDV"),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.event_busy), findsOneWidget);

      final callButton = find.descendant(
        of: find.byKey(const Key('work_queue_pending_appointment_row_rdv1')),
        matching: find.text('Appeler'),
      );
      expect(callButton, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('work_queue_pending_appointment_row_rdv1')),
          matching: find.byIcon(Icons.call),
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(callButton);
      await tester.tap(callButton);
      await tester.pumpAndSettle();
      expect(find.text('Agenda extra=rdv1'), findsOneWidget);
    });

    testWidgets(
        '#8128 (récidive #6853) : nom patient long → heure en préfixe, à '
        "l'abri de l'ellipse de fin", (tester) async {
      when(() => cubit.state).thenReturn(
        const PatientMessagesSummaryLoaded(
          unreadCount: 0,
          urgentUnreadCount: 0,
        ),
      );
      await tester.pumpWidget(
        _wrap(
          cubit,
          quotesCubit,
          pendingAppointmentsToday: [
            _pendingEntry(
              'rdv-long',
              patientName: 'Anne-Sophie Vandenbroucke',
              startsAt: DateTime(2026, 8, 16, 12, 0),
            ),
          ],
        ),
      );

      // Le nom (25 caractères) dépasse largement le seuil qui faisait
      // tomber l'ellipse sur l'heure quand celle-ci était en fin de
      // chaîne (#8128) — l'heure est désormais en tête, insensible à la
      // longueur du nom.
      expect(
        find.text(
          "12:00 — Anne-Sophie Vandenbroucke n'a pas confirmé son RDV",
        ),
        findsOneWidget,
      );
    });

    testWidgets('#5376 : aucun RDV non confirmé → pas de ligne', (
      tester,
    ) async {
      when(() => cubit.state).thenReturn(
        const PatientMessagesSummaryLoaded(
          unreadCount: 0,
          urgentUnreadCount: 0,
        ),
      );
      await tester.pumpWidget(_wrap(cubit, quotesCubit));

      expect(find.byIcon(Icons.event_busy), findsNothing);
      expect(find.textContaining("n'a pas confirmé"), findsNothing);
    });

    testWidgets('#5377 : aucun devis expirant → ligne masquée', (tester) async {
      when(() => cubit.state).thenReturn(
        const PatientMessagesSummaryLoaded(
          unreadCount: 0,
          urgentUnreadCount: 0,
        ),
      );
      when(() => quotesCubit.state)
          .thenReturn(const ExpiringQuotesSummaryLoaded(quotes: []));
      await tester.pumpWidget(_wrap(cubit, quotesCubit));

      expect(
        find.byKey(const Key('work_queue_expiring_quotes_row')),
        findsNothing,
      );
      expect(find.textContaining('devis expirent'), findsNothing);
    });
  });
}
