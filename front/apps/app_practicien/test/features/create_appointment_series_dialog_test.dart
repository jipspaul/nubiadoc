// #4088 : formulaire de création d'une série de RDV liés (ortho, parodonto,
// chirurgie multi-séances) — le point d'entrée UI praticien qui manquait
// totalement côté front pour POST /v1/cabinet/appointments/series.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/agenda/create_appointment_series_dialog.dart';

final _patient = CabinetPatient(
  id: 'pat-1',
  cabinetId: 'cab-1',
  firstName: 'Marc',
  lastName: 'Dubois',
  createdAt: DateTime(2026, 1, 1),
);

Widget _wrapOpenButton(void Function(CreateAppointmentSeriesResult?) onResult) {
  return MaterialApp(
    theme: NubiaTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final result = await showDialog<CreateAppointmentSeriesResult>(
                context: context,
                builder: (_) => CreateAppointmentSeriesDialog(patient: _patient),
              );
              onResult(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('affiche le nom du patient dans le titre', (tester) async {
    await tester.pumpWidget(_wrapOpenButton((_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('create_series_dialog')), findsOneWidget);
    expect(find.text('Série de RDV — Marc Dubois'), findsOneWidget);
  });

  testWidgets('valider sans date choisie affiche un message et ne ferme pas',
      (tester) async {
    CreateAppointmentSeriesResult? result;
    await tester.pumpWidget(_wrapOpenButton((r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('create_series_submit')));
    await tester.pump();

    expect(find.text('Choisissez la date de la 1ère séance.'), findsOneWidget);
    expect(find.byKey(const Key('create_series_dialog')), findsOneWidget);
    expect(result, isNull);
  });

  testWidgets(
      'choisir la date puis valider génère 3 occurrences espacées de 7 jours par défaut',
      (tester) async {
    CreateAppointmentSeriesResult? result;
    await tester.pumpWidget(_wrapOpenButton((r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choisir la date'));
    await tester.pumpAndSettle();
    // Le date picker présélectionne déjà `initialDate` (demain) — valider
    // directement via OK évite de dépendre du mois affiché par le calendrier.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Séances prévues (3)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('create_series_submit')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.occurrences, hasLength(3));
    expect(
      result!.occurrences[1].startsAt.difference(result!.occurrences[0].startsAt),
      const Duration(days: 7),
    );
    expect(
      result!.occurrences[0].endsAt.difference(result!.occurrences[0].startsAt),
      const Duration(minutes: 30),
    );
  });
}
