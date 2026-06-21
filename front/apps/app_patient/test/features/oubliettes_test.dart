import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_patient/features/oubliettes/oubliettes_bloc.dart';
import 'package:app_patient/features/oubliettes/oubliettes_page.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockOubliettesBloc
    extends MockBloc<OubliettesEvent, OubliettesState>
    implements OubliettesBloc {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(OubliettesBloc bloc) => MaterialApp(
      home: BlocProvider<OubliettesBloc>.value(
        value: bloc,
        child: const Scaffold(body: OubliettesPage()),
      ),
    );

OublietteItem _item(String id) => OublietteItem(
      id: id,
      title: 'Document $id',
      seenAt: DateTime(2026, 6, 19),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('OubliettesPage — empty state', () {
    testWidgets('affiche NubiaEmptyState quand Loaded([]) est émis',
        (tester) async {
      final bloc = MockOubliettesBloc();
      when(() => bloc.state).thenReturn(const OubliettesLoaded([]));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('oubliettes_empty')), findsOneWidget);
      expect(find.byType(NubiaEmptyState), findsOneWidget);
    });
  });

  group('OubliettesPage — loaded state', () {
    testWidgets('affiche 3 cartes quand 3 items sont chargés', (tester) async {
      final bloc = MockOubliettesBloc();
      when(() => bloc.state).thenReturn(
        OubliettesLoaded([_item('1'), _item('2'), _item('3')]),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('oubliettes_list')), findsOneWidget);
      expect(find.byKey(const Key('oubliette_1')), findsOneWidget);
      expect(find.byKey(const Key('oubliette_2')), findsOneWidget);
      expect(find.byKey(const Key('oubliette_3')), findsOneWidget);
    });
  });
}
