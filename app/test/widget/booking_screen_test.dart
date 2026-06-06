import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/presentation/features/appointments/bloc/booking_bloc.dart';
import 'package:nubia_patient/presentation/features/appointments/pages/booking_screen.dart';
import 'package:nubia_patient/presentation/features/appointments/widgets/slot_grid.dart';

class MockBookingBloc extends MockBloc<BookingEvent, BookingState>
    implements BookingBloc {}

final _now = DateTime.now();

List<AppointmentSlot> _slots({int count = 3}) => List.generate(
      count,
      (i) => AppointmentSlot(
        id: 'slot-$i',
        startsAt: _now.add(Duration(days: i + 1)),
        duration: const Duration(minutes: 30),
        available: i != 1, // slot index 1 is unavailable
      ),
    );

Widget _wrapBooking(BookingBloc bloc) {
  return MaterialApp(
    home: BlocProvider<BookingBloc>.value(
      value: bloc,
      child: const BookingScreen(),
    ),
  );
}

void main() {
  late MockBookingBloc bloc;

  setUp(() {
    bloc = MockBookingBloc();
  });

  tearDown(() => bloc.close());

  testWidgets(
    'BookingScreen affiche un indicateur de chargement en état Loading',
    (tester) async {
      when(() => bloc.state).thenReturn(const BookingLoading());

      await tester.pumpWidget(_wrapBooking(bloc));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  testWidgets(
    'BookingScreen affiche les créneaux disponibles en état BookingLoaded',
    (tester) async {
      final slots = _slots();
      when(() => bloc.state).thenReturn(
        BookingLoaded(slots: slots),
      );

      await tester.pumpWidget(_wrapBooking(bloc));

      // SlotGrid is rendered — at least one SlotChip per available slot.
      expect(find.byType(SlotGrid), findsOneWidget);
      // The motif field is visible.
      expect(find.byType(TextFormField), findsOneWidget);
      // Confirm button is present.
      expect(find.text('Confirmer le rendez-vous'), findsOneWidget);
    },
  );

  testWidgets(
    'BookingScreen affiche un message d\'erreur en état BookingError',
    (tester) async {
      when(() => bloc.state)
          .thenReturn(const BookingError('Erreur réseau.'));

      await tester.pumpWidget(_wrapBooking(bloc));

      expect(find.text('Erreur réseau.'), findsOneWidget);
    },
  );
}
