import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_secretariat/features/dashboard/patient_messages_summary_cubit.dart';
import 'package:app_secretariat/features/dashboard/widgets/work_queue_card.dart';

class _MockPatientMessagesSummaryCubit
    extends MockCubit<PatientMessagesSummaryState>
    implements PatientMessagesSummaryCubit {}

Widget _wrap(
  PatientMessagesSummaryCubit cubit, {
  int waitingCount = 0,
  int? oldestWaitingRequestAgeDays,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: BlocProvider<PatientMessagesSummaryCubit>.value(
            value: cubit,
            child: WorkQueueCard(
              waitingCount: waitingCount,
              oldestWaitingRequestAgeDays: oldestWaitingRequestAgeDays,
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/messages',
        builder: (context, state) => const Scaffold(body: Text('Messagerie')),
      ),
      GoRoute(
        path: '/liste-attente',
        builder: (context, state) =>
            const Scaffold(body: Text('Liste d\'attente')),
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

    setUp(() {
      cubit = _MockPatientMessagesSummaryCubit();
    });

    testWidgets('affiche le squelette de chargement', (tester) async {
      when(() => cubit.state).thenReturn(const PatientMessagesSummaryLoading());
      await tester.pumpWidget(_wrap(cubit));
      expect(find.byKey(const Key('work_queue_card_loading')), findsOneWidget);
    });

    testWidgets('affiche une erreur', (tester) async {
      when(() => cubit.state)
          .thenReturn(const PatientMessagesSummaryError(message: 'Erreur test'));
      await tester.pumpWidget(_wrap(cubit));
      expect(find.byKey(const Key('work_queue_card_error')), findsOneWidget);
      expect(find.text('Erreur test'), findsOneWidget);
    });

    testWidgets(
        '#5379 : titre = messages non lus, sous-titre = urgent, Ouvrir → /messages',
        (tester) async {
      when(() => cubit.state).thenReturn(
        const PatientMessagesSummaryLoaded(
          unreadCount: 4,
          urgentUnreadCount: 1,
          urgentPatientName: 'Ahmed Belkacem',
        ),
      );
      await tester.pumpWidget(_wrap(cubit));

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
      expect(find.text('Messagerie'), findsOneWidget);
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
        _wrap(cubit, waitingCount: 3, oldestWaitingRequestAgeDays: 5),
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
        '#5378 : liste d\'attente vide → pas de sous-titre d\'ancienneté',
        (tester) async {
      when(() => cubit.state).thenReturn(
        const PatientMessagesSummaryLoaded(
          unreadCount: 0,
          urgentUnreadCount: 0,
        ),
      );
      await tester.pumpWidget(_wrap(cubit));

      expect(find.text('0 demandes de créneau sans réponse'), findsOneWidget);
      expect(find.textContaining('La plus ancienne'), findsNothing);
    });

    testWidgets('aucun message urgent → pas de sous-titre', (tester) async {
      when(() => cubit.state).thenReturn(
        const PatientMessagesSummaryLoaded(
          unreadCount: 0,
          urgentUnreadCount: 0,
        ),
      );
      await tester.pumpWidget(_wrap(cubit));

      expect(find.text('0 messages patients non lus'), findsOneWidget);
      expect(find.textContaining('marqué urgent'), findsNothing);
    });
  });
}
