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

Widget _wrap(PatientMessagesSummaryCubit cubit) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: BlocProvider<PatientMessagesSummaryCubit>.value(
            value: cubit,
            child: const WorkQueueCard(),
          ),
        ),
      ),
      GoRoute(
        path: '/messages',
        builder: (context, state) => const Scaffold(body: Text('Messagerie')),
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

      expect(find.text('Ouvrir'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);

      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      expect(find.text('Messagerie'), findsOneWidget);
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
