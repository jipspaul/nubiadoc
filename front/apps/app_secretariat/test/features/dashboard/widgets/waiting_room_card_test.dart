import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_secretariat/features/dashboard/waiting_room_summary_cubit.dart';
import 'package:app_secretariat/features/dashboard/widgets/waiting_room_card.dart';

class _MockWaitingRoomSummaryCubit extends MockCubit<WaitingRoomSummaryState>
    implements WaitingRoomSummaryCubit {}

Widget _wrap(WaitingRoomSummaryCubit cubit) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(
        body: BlocProvider<WaitingRoomSummaryCubit>.value(
          value: cubit,
          child: const WaitingRoomCard(),
        ),
      ),
    );

void main() {
  group('WaitingRoomCard', () {
    late _MockWaitingRoomSummaryCubit cubit;

    setUp(() {
      cubit = _MockWaitingRoomSummaryCubit();
    });

    testWidgets('affiche le squelette de chargement', (tester) async {
      when(() => cubit.state).thenReturn(const WaitingRoomSummaryLoading());
      await tester.pumpWidget(_wrap(cubit));
      expect(find.byKey(const Key('waiting_room_card_loading')), findsOneWidget);
    });

    testWidgets('affiche une erreur', (tester) async {
      when(() => cubit.state)
          .thenReturn(const WaitingRoomSummaryError(message: 'Erreur test'));
      await tester.pumpWidget(_wrap(cubit));
      expect(find.byKey(const Key('waiting_room_card_error')), findsOneWidget);
      expect(find.text('Erreur test'), findsOneWidget);
    });

    testWidgets(
        '#5381 : effectif + attente moyenne/la plus longue, lien Ouvrir',
        (tester) async {
      when(() => cubit.state).thenReturn(
        const WaitingRoomSummaryLoaded(
          presentCount: 5,
          averageWaitMinutes: 14,
          longestWaitMinutes: 32,
        ),
      );
      await tester.pumpWidget(_wrap(cubit));

      expect(find.byKey(const Key('waiting_room_card')), findsOneWidget);
      expect(find.text('Salle d\'attente'), findsOneWidget);

      expect(
        find.byKey(const Key('waiting_room_card_summary_row')),
        findsOneWidget,
      );
      expect(find.text('5 personne(s) présente(s)'), findsOneWidget);
      expect(
        find.text('Attente moyenne 14 min · une depuis 32 min'),
        findsOneWidget,
      );
      expect(find.text('5'), findsOneWidget);

      expect(find.text('Ouvrir'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
      expect(
        find.byKey(const Key('waiting_room_card_open_link')),
        findsOneWidget,
      );
    });

    testWidgets('salle vide → sous-titre dédié, compteur non warning',
        (tester) async {
      when(() => cubit.state).thenReturn(
        const WaitingRoomSummaryLoaded(
          presentCount: 0,
          averageWaitMinutes: 0,
          longestWaitMinutes: 0,
        ),
      );
      await tester.pumpWidget(_wrap(cubit));

      expect(find.text('0 personne(s) présente(s)'), findsOneWidget);
      expect(
        find.text('Aucun patient en salle d\'attente.'),
        findsOneWidget,
      );
    });
  });
}
