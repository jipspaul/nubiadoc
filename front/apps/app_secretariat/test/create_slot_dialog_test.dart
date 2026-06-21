import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_secretariat/features/bookable_slots/bookable_slots_bloc.dart';
import 'package:app_secretariat/features/bookable_slots/bookable_slots_event.dart';
import 'package:app_secretariat/features/bookable_slots/bookable_slots_state.dart';
import 'package:app_secretariat/features/bookable_slots/create_slot_dialog.dart';

class _MockBookableSlotsBloc
    extends MockBloc<BookableSlotsEvent, BookableSlotsState>
    implements BookableSlotsBloc {}

void main() {
  setUpAll(() {
    registerFallbackValue(const BookableSlotsLoadRequested());
  });

  group('CreateSlotDialog', () {
    late _MockBookableSlotsBloc bloc;

    setUp(() {
      bloc = _MockBookableSlotsBloc();
      when(() => bloc.state).thenReturn(const BookableSlotsLoaded([]));
    });

    Widget buildDialog({
      DateTime? initialDate,
      TimeOfDay? initialStart,
      TimeOfDay? initialEnd,
      int initialCapacity = 1,
    }) =>
        MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<BookableSlotsBloc>.value(
            value: bloc,
            child: CreateSlotDialog(
              initialDate: initialDate,
              initialStart: initialStart,
              initialEnd: initialEnd,
              initialCapacity: initialCapacity,
            ),
          ),
        );

    testWidgets(
        'remplir et confirmer dispatch CreateSlotRequested au bloc',
        (tester) async {
      await tester.pumpWidget(buildDialog(
        initialDate: DateTime(2026, 6, 21),
        initialStart: const TimeOfDay(hour: 9, minute: 0),
        initialEnd: const TimeOfDay(hour: 10, minute: 0),
        initialCapacity: 1,
      ));
      await tester.pumpAndSettle();

      // Bouton Créer doit être actif
      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('create_button')),
      );
      expect(button.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('create_button')));
      await tester.pump();

      verify(() => bloc.add(any(that: isA<CreateSlotRequested>()))).called(1);
    });

    testWidgets(
        'bouton Créer désactivé quand heure début >= heure fin',
        (tester) async {
      await tester.pumpWidget(buildDialog(
        initialDate: DateTime(2026, 6, 21),
        initialStart: const TimeOfDay(hour: 10, minute: 0),
        initialEnd: const TimeOfDay(hour: 9, minute: 0),
        initialCapacity: 1,
      ));
      await tester.pumpAndSettle();

      final button = tester.widget<ElevatedButton>(
        find.byKey(const Key('create_button')),
      );
      expect(button.onPressed, isNull);
    });
  });
}
