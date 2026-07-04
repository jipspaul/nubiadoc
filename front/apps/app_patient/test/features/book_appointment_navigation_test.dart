import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_patient/features/appointments/appointments_bloc.dart';
import 'package:app_patient/features/appointments/appointments_event.dart';
import 'package:app_patient/features/appointments/appointments_state.dart';
import 'package:app_patient/features/booking/book_appointment_page.dart';

class _MockAppointmentsBloc
    extends MockBloc<AppointmentsEvent, AppointmentsState>
    implements AppointmentsBloc {}

void main() {
  late _MockAppointmentsBloc mockBloc;

  setUp(() {
    mockBloc = _MockAppointmentsBloc();
    when(() => mockBloc.state).thenReturn(const AppointmentsInitial());
    when(() => mockBloc.stream).thenAnswer((_) => const Stream.empty());
    GetIt.instance.registerFactory<AppointmentsBloc>(() => mockBloc);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets(
      'tap FAB "Booker un RDV" navigue vers /book et affiche le formulaire',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/mes-rdv',
      routes: [
        GoRoute(
          path: '/mes-rdv',
          builder: (context, __) => Scaffold(
            floatingActionButton: FloatingActionButton.extended(
              key: const Key('book_rdv_fab'),
              onPressed: () => context.go('/book'),
              icon: const Icon(Icons.add),
              label: const Text('Booker un RDV'),
            ),
            body: const SizedBox(),
          ),
        ),
        GoRoute(
          path: '/book',
          builder: (_, __) => const BookAppointmentPage(),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_rdv_fab')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book_appointment_scaffold')), findsOneWidget);
    expect(find.byKey(const Key('search_field')), findsOneWidget);
  });
}
