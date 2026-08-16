import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/dashboard/cash_collection_cubit.dart';
import 'package:app_secretariat/features/dashboard/widgets/cash_collection_card.dart';

class _MockCashCollectionCubit extends MockCubit<CashCollectionState>
    implements CashCollectionCubit {}

Widget _wrap(CashCollectionCubit cubit) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(
        body: BlocProvider<CashCollectionCubit>.value(
          value: cubit,
          child: const CashCollectionCard(),
        ),
      ),
    );

void main() {
  group('CashCollectionCard', () {
    late _MockCashCollectionCubit cubit;

    setUp(() {
      cubit = _MockCashCollectionCubit();
    });

    testWidgets('affiche le squelette de chargement', (tester) async {
      when(() => cubit.state).thenReturn(const CashCollectionLoading());
      await tester.pumpWidget(_wrap(cubit));
      expect(find.byKey(const Key('cash_collection_loading')), findsOneWidget);
    });

    testWidgets('affiche une erreur', (tester) async {
      when(() => cubit.state)
          .thenReturn(const CashCollectionError(message: 'Erreur test'));
      await tester.pumpWidget(_wrap(cubit));
      expect(find.byKey(const Key('cash_collection_error')), findsOneWidget);
      expect(find.text('Erreur test'), findsOneWidget);
    });

    testWidgets(
        '#5382 : trois lignes — encaissé, reste à encaisser, impayés — '
        'montants formatés en euros', (tester) async {
      when(() => cubit.state).thenReturn(
        const CashCollectionLoaded(
          summary: CashCollectionSummary(
            collectedTodayCents: 184200,
            collectedTodayPaymentCount: 7,
            remainingTodayCents: 36050,
            remainingTodayPatientCount: 2,
            closingHour: 19,
            unpaidCents: 291800,
            unpaidPatientCount: 7,
          ),
        ),
      );
      await tester.pumpWidget(_wrap(cubit));

      expect(find.byKey(const Key('cash_collection_card')), findsOneWidget);
      expect(find.text('Encaissements du jour'), findsOneWidget);

      expect(find.byKey(const Key('cash_collected_today_row')), findsOneWidget);
      expect(find.text('Encaissé aujourd’hui'), findsOneWidget);
      expect(find.text('7 paiement(s)'), findsOneWidget);
      expect(find.text('1 842,00 €'), findsOneWidget);

      expect(find.byKey(const Key('cash_remaining_today_row')), findsOneWidget);
      expect(find.text('Reste à encaisser'), findsOneWidget);
      expect(find.text('2 patient(s) avant 19h'), findsOneWidget);
      expect(find.text('360,50 €'), findsOneWidget);

      expect(find.byKey(const Key('cash_unpaid_row')), findsOneWidget);
      expect(find.text('Impayés du cabinet'), findsOneWidget);
      expect(find.text('7 patient(s) concerné(s)'), findsOneWidget);
      expect(find.text('2 918,00 €'), findsOneWidget);
    });
  });
}
