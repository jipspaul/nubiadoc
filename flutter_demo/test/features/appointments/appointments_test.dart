import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_demo/features/appointments/bloc/appointment_bloc.dart';
import 'package:flutter_demo/features/appointments/bloc/appointment_event.dart';
import 'package:flutter_demo/features/appointments/bloc/appointment_state.dart';
import 'package:flutter_demo/features/appointments/appointments_list_screen.dart';
import 'package:flutter_demo/features/appointments/appointment_detail_screen.dart';
import 'package:flutter_demo/features/appointments/book_appointment_screen.dart';
import 'package:flutter_demo/features/appointments/models/appointment.dart';
import 'package:flutter_demo/features/appointments/widgets/appointment_card.dart';
import 'package:flutter_demo/features/appointments/widgets/appointment_status_chip.dart';
import 'package:flutter_demo/theme/nubia_theme.dart';

class MockAppointmentBloc
    extends MockBloc<AppointmentEvent, AppointmentState>
    implements AppointmentBloc {}

final _mockAppointment = Appointment(
  id: 'apt-001',
  providerName: 'Dr Martin',
  motif: 'Pose prothèse',
  startsAt: DateTime.utc(2026, 7, 10, 9, 30),
  status: AppointmentStatus.confirmed,
  address: '12 rue de la Paix, 75001 Paris',
);

Widget _wrap(Widget child, AppointmentBloc bloc) {
  return MaterialApp(
    theme: NubiaTheme.light,
    home: BlocProvider<AppointmentBloc>.value(value: bloc, child: child),
  );
}

void main() {
  setUpAll(() {
    // AppointmentEvent est sealed — on enregistre une sous-classe concrète comme fallback.
    registerFallbackValue(const AppointmentLoadRequested());
  });

  late MockAppointmentBloc mockBloc;

  setUp(() {
    mockBloc = MockAppointmentBloc();
  });

  group('AppointmentsListScreen', () {
    testWidgets('renders without throwing', (tester) async {
      when(() => mockBloc.state)
          .thenReturn(AppointmentListLoaded([_mockAppointment]));
      await tester.pumpWidget(
        _wrap(const AppointmentsListScreen(), mockBloc),
      );
      expect(find.byType(AppointmentsListScreen), findsOneWidget);
    });

    testWidgets('shows loading indicator on AppointmentLoading', (tester) async {
      when(() => mockBloc.state).thenReturn(const AppointmentLoading());
      await tester.pumpWidget(
        _wrap(const AppointmentsListScreen(), mockBloc),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows appointment card when list is loaded', (tester) async {
      when(() => mockBloc.state)
          .thenReturn(AppointmentListLoaded([_mockAppointment]));
      await tester.pumpWidget(
        _wrap(const AppointmentsListScreen(), mockBloc),
      );
      expect(find.byType(AppointmentCard), findsOneWidget);
      expect(find.textContaining('Dr Martin'), findsOneWidget);
    });

    testWidgets('shows empty message when list is empty', (tester) async {
      when(() => mockBloc.state)
          .thenReturn(const AppointmentListLoaded([]));
      await tester.pumpWidget(
        _wrap(const AppointmentsListScreen(), mockBloc),
      );
      expect(find.text('Aucun rendez-vous'), findsOneWidget);
    });

    testWidgets('shows error view on AppointmentError', (tester) async {
      when(() => mockBloc.state)
          .thenReturn(const AppointmentError('Erreur réseau'));
      await tester.pumpWidget(
        _wrap(const AppointmentsListScreen(), mockBloc),
      );
      expect(find.text('Erreur réseau'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('retry button dispatches AppointmentLoadRequested',
        (tester) async {
      when(() => mockBloc.state)
          .thenReturn(const AppointmentError('Erreur réseau'));
      await tester.pumpWidget(
        _wrap(const AppointmentsListScreen(), mockBloc),
      );
      await tester.tap(find.text('Réessayer'));
      await tester.pump();
      verify(() => mockBloc.add(const AppointmentLoadRequested())).called(1);
    });
  });

  group('AppointmentDetailScreen', () {
    testWidgets('renders without throwing', (tester) async {
      when(() => mockBloc.state)
          .thenReturn(AppointmentDetailLoaded(_mockAppointment));
      await tester.pumpWidget(
        _wrap(
          AppointmentDetailScreen(appointmentId: _mockAppointment.id),
          mockBloc,
        ),
      );
      expect(find.byType(AppointmentDetailScreen), findsOneWidget);
    });

    testWidgets('shows provider name and motif', (tester) async {
      when(() => mockBloc.state)
          .thenReturn(AppointmentDetailLoaded(_mockAppointment));
      await tester.pumpWidget(
        _wrap(
          AppointmentDetailScreen(appointmentId: _mockAppointment.id),
          mockBloc,
        ),
      );
      expect(find.text('Dr Martin'), findsOneWidget);
      expect(find.text('Pose prothèse'), findsOneWidget);
    });

    testWidgets('shows cancel button when status is confirmed', (tester) async {
      when(() => mockBloc.state)
          .thenReturn(AppointmentDetailLoaded(_mockAppointment));
      await tester.pumpWidget(
        _wrap(
          AppointmentDetailScreen(appointmentId: _mockAppointment.id),
          mockBloc,
        ),
      );
      expect(find.byKey(const Key('btn_cancel')), findsOneWidget);
    });

    testWidgets('cancel button dispatches AppointmentCancelRequested',
        (tester) async {
      when(() => mockBloc.state)
          .thenReturn(AppointmentDetailLoaded(_mockAppointment));
      await tester.pumpWidget(
        _wrap(
          AppointmentDetailScreen(appointmentId: _mockAppointment.id),
          mockBloc,
        ),
      );
      await tester.tap(find.byKey(const Key('btn_cancel')));
      await tester.pump();
      verify(
        () => mockBloc.add(
          AppointmentCancelRequested(id: _mockAppointment.id),
        ),
      ).called(1);
    });
  });

  group('BookAppointmentScreen', () {
    testWidgets('renders without throwing', (tester) async {
      when(() => mockBloc.state).thenReturn(const AppointmentInitial());
      await tester.pumpWidget(
        _wrap(const BookAppointmentScreen(), mockBloc),
      );
      expect(find.byType(BookAppointmentScreen), findsOneWidget);
    });

    testWidgets('shows motif and provider fields', (tester) async {
      when(() => mockBloc.state).thenReturn(const AppointmentInitial());
      await tester.pumpWidget(
        _wrap(const BookAppointmentScreen(), mockBloc),
      );
      expect(find.byKey(const Key('field_provider')), findsOneWidget);
      expect(find.byKey(const Key('field_motif')), findsOneWidget);
    });

    testWidgets('submit dispatches AppointmentBookRequested', (tester) async {
      when(() => mockBloc.state).thenReturn(const AppointmentInitial());
      // Capture all add() calls so we can verify type without using `any`.
      final captured = <AppointmentEvent>[];
      when(() => mockBloc.add(captureAny()))
          .thenAnswer((i) => captured.add(i.positionalArguments.first as AppointmentEvent));
      await tester.pumpWidget(
        _wrap(const BookAppointmentScreen(), mockBloc),
      );
      await tester.enterText(find.byKey(const Key('field_motif')), 'Détartrage');
      await tester.pump();
      await tester.tap(find.byKey(const Key('btn_submit')));
      await tester.pump();
      expect(captured.any((e) => e is AppointmentBookRequested), isTrue);
    });
  });

  group('AppointmentCard', () {
    testWidgets('renders without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: AppointmentCard(
              appointment: _mockAppointment,
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.byType(AppointmentCard), findsOneWidget);
    });
  });

  group('AppointmentStatusChip', () {
    for (final status in AppointmentStatus.values) {
      testWidgets('renders $status without throwing', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: Scaffold(
              body: AppointmentStatusChip(status: status),
            ),
          ),
        );
        expect(find.byType(AppointmentStatusChip), findsOneWidget);
      });
    }
  });
}
