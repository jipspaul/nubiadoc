import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/home/widgets/hero_appointment_card.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

Appointment _appointment(AppointmentStatus status) => Appointment(
      id: 'rdv-1',
      cabinetId: 'cab-dubois',
      practitionerName: 'Dr Hugo Marin',
      practitionerSpecialty: 'Généraliste',
      startsAt: DateTime.now().add(const Duration(days: 1)),
      duration: const Duration(minutes: 30),
      motif: '',
      status: status,
    );

void main() {
  // #8628 : la carte héros promouvait un RDV `requested` (non confirmé par
  // le cabinet) à l'identique d'un RDV `confirmed` — aucune pastille ne
  // distinguait les deux, alors que le MÊME rendez-vous porte « En attente »
  // dans l'onglet « Mes RDV ».
  testWidgets('#8628 : RDV requested affiche la pastille "En attente"',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: HeroAppointmentCard(
            upcomingAppointments: 1,
            nextAppointment: _appointment(AppointmentStatus.requested),
          ),
        ),
      ),
    );

    expect(find.text('En attente'), findsOneWidget);
  });

  testWidgets('#8628 : RDV confirmed n\'affiche aucune pastille de statut',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: HeroAppointmentCard(
            upcomingAppointments: 1,
            nextAppointment: _appointment(AppointmentStatus.confirmed),
          ),
        ),
      ),
    );

    expect(find.text('Confirmé'), findsNothing);
    expect(find.text('En attente'), findsNothing);
  });
}
