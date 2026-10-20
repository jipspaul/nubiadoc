//! Test : `StockPage` (#8213) — chaque carte de demande doit nommer la
//! pharmacie destinataire et la date d'envoi, comme son jumeau corrigé côté
//! secrétariat (ronde R132) ; avant le correctif, le `Row(spaceBetween)` de
//! la carte n'avait qu'un seul enfant (`StatusPill`) et ces deux informations
//! n'étaient lues nulle part.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/stock/stock_bloc.dart';
import 'package:app_practicien/features/stock/stock_event.dart';
import 'package:app_practicien/features/stock/stock_page.dart';
import 'package:app_practicien/features/stock/stock_state.dart';

class MockStockBloc extends MockBloc<StockEvent, StockState>
    implements StockBloc {}

final _request = StockRequest(
  id: 'req-1',
  pharmacyId: 'pharma-1',
  pharmacy: const Pharmacy(
    id: 'pharma-1',
    name: 'Pharmacie du Rhône',
    address: '12 quai du Rhône, 69006, Lyon',
    phone: '+33 4 78 00 00 84',
  ),
  items: const [
    StockRequestItem(label: 'Gants taille M', quantity: 4),
  ],
  status: StockRequestStatus.fulfilled,
  createdAt: DateTime(2026, 10, 7, 15, 0),
);

Widget _wrap(StockBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<StockBloc>.value(
        value: bloc,
        child: const StockPage(),
      ),
    );

void main() {
  group('StockPage (widget)', () {
    testWidgets(
        'la carte nomme la pharmacie destinataire, son adresse/téléphone '
        'et la date d\'envoi', (tester) async {
      final bloc = MockStockBloc();
      when(() => bloc.state).thenReturn(StockLoaded([_request]));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.text('Pharmacie du Rhône'), findsOneWidget);
      expect(
        find.text('12 quai du Rhône, 69006, Lyon · +33 4 78 00 00 84'),
        findsOneWidget,
      );
      expect(find.text('07/10 · 15:00'), findsOneWidget);
    });

    testWidgets(
        'retombe sur l\'id pharmacie sans masquer la carte quand la '
        'pharmacie n\'est pas résolue', (tester) async {
      final bloc = MockStockBloc();
      when(() => bloc.state).thenReturn(StockLoaded([
        StockRequest(
          id: 'req-2',
          pharmacyId: 'pharma-unresolved',
          items: const [
            StockRequestItem(label: 'Compresses stériles', quantity: 2),
          ],
          status: StockRequestStatus.sent,
          createdAt: DateTime(2026, 10, 7, 15, 0),
        ),
      ]));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.text('pharma-unresolved'), findsOneWidget);
      expect(find.text('07/10 · 15:00'), findsOneWidget);
    });
  });
}
