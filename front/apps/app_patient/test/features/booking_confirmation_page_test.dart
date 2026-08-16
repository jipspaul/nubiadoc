import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_patient/features/appointments/booking_confirmation_page.dart';

final _appointment = Appointment(
  id: 'appt-1',
  cabinetId: 'cab-1',
  practitionerName: 'Dr Amélie Rousseau',
  practitionerSpecialty: 'Chirurgien-dentiste',
  startsAt: DateTime.now().add(const Duration(days: 1)),
  duration: const Duration(minutes: 30),
  motif: 'Contrôle annuel',
  status: AppointmentStatus.requested,
);

void main() {
  group('BookingConfirmationPage', () {
    testWidgets('#5364 : un seul CTA principal — pas de bandeau app par défaut',
        (tester) async {
      await tester.pumpApp(
        BookingConfirmationPage(appointment: _appointment),
      );

      expect(find.byKey(const Key('booking_confirmation_view_appointments')),
          findsOneWidget);
      expect(find.byKey(const Key('booking_confirmation_dismiss')),
          findsOneWidget);
      // #5364 : hors web, l'utilisateur est déjà dans l'app — pas de
      // proposition de téléchargement.
      expect(find.byKey(const Key('booking_confirmation_download_app')),
          findsNothing);
    });

    testWidgets(
        '#5364 : le téléchargement de l\'app n\'est proposé qu\'après la confirmation',
        (tester) async {
      await tester.pumpApp(
        BookingConfirmationPage(
          appointment: _appointment,
          showAppDownloadPrompt: true,
        ),
      );

      final downloadFinder =
          find.byKey(const Key('booking_confirmation_download_app'));
      expect(downloadFinder, findsOneWidget);
      // Reste une action secondaire (tertiaire) : la seule action principale
      // pleine largeur de l'écran demeure « Voir mes RDV ».
      expect(find.text("Télécharger l'app"), findsOneWidget);
      expect(find.text('Voir mes RDV'), findsOneWidget);

      await tester.ensureVisible(downloadFinder);
      await tester.pumpAndSettle();
      await tester.tap(downloadFinder);
      await tester.pump();
      expect(
        find.text('Lien de téléchargement bientôt disponible.'),
        findsOneWidget,
      );
    });

    testWidgets('affiche le récapitulatif du rendez-vous', (tester) async {
      await tester.pumpApp(
        BookingConfirmationPage(appointment: _appointment),
      );

      expect(
        find.textContaining('Dr Amélie Rousseau'),
        findsOneWidget,
      );
      expect(find.text('Contrôle annuel'), findsOneWidget);
    });
  });
}
