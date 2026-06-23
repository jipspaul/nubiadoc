import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:app_patient/features/booking/book_appointment_page.dart';

void main() {
  testWidgets('tap FAB "Booker un RDV" navigue vers /book', (tester) async {
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

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book_rdv_fab')));
    await tester.pumpAndSettle();

    expect(find.text('Booking flow viendra (FR1.33+)'), findsOneWidget);
  });
}
