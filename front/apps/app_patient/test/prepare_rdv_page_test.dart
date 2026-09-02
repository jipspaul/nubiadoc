import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/mes_rdv/appointment_formatting.dart';
import 'package:app_patient/features/mes_rdv/prepare_rdv_page.dart';

import 'helpers/mock_repositories.dart';

// ── Fake prefs service ───────────────────────────────────────────────────────

class _FakePrefsService implements PrepareRdvPrefsService {
  Set<String> checked = {};

  @override
  Future<Set<String>> loadChecked(String rdvId) async => Set.from(checked);

  @override
  Future<void> saveChecked(String rdvId, Set<String> ids) async {
    checked = Set.from(ids);
  }
}

// ── Fixtures ─────────────────────────────────────────────────────────────────

final _kReminderAt = DateTime.utc(2026, 9, 2, 7);

final _kPreparation = AppointmentPreparation(
  address: '12 rue de la Paix, 75001 Paris',
  providerName: 'Dr Claire Lefèvre',
  access: const PreparationAccess(
    doorCode: 'A1234',
    parking: true,
    pmr: true,
  ),
  reminderAt: _kReminderAt,
  items: const [
    PreparationItem(label: 'Carte Vitale', required: true),
    PreparationItem(label: 'Carte mutuelle', required: true),
    PreparationItem(label: 'Ordonnance', required: false),
  ],
);

// ── Helper ───────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) => MaterialApp(theme: NubiaTheme.light, home: child);

void main() {
  late MockAppointmentRepository repository;

  setUp(() {
    repository = MockAppointmentRepository();
  });

  group('PrepareRdvPage — loaded state', () {
    testWidgets(
        'affiche les items, le titre fixe et les infos pratiques (accès, '
        'praticien, rappel) — régression #6203', (tester) async {
      when(() => repository.getPreparation('rdv-1'))
          .thenAnswer((_) async => Right(_kPreparation));

      await tester.pumpWidget(_wrap(PrepareRdvPage(
        appointmentId: 'rdv-1',
        prefsService: _FakePrefsService(),
        useCase: GetAppointmentPreparationUseCase(repository),
      )));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('item_carte_vitale')), findsOneWidget);
      expect(find.byKey(const Key('item_carte_mutuelle')), findsOneWidget);
      expect(find.byKey(const Key('item_ordonnance')), findsOneWidget);

      // Le titre d'AppBar n'est plus remplacé par l'adresse tronquée (#6203).
      expect(find.widgetWithText(AppBar, 'Préparer mon RDV'), findsOneWidget);

      // Infos pratiques restituées : adresse, praticien, accès, rappel.
      expect(find.text('12 rue de la Paix, 75001 Paris'), findsOneWidget);
      expect(find.text('Dr Claire Lefèvre'), findsOneWidget);
      expect(find.text('Parking disponible'), findsOneWidget);
      expect(find.text('Accès PMR'), findsOneWidget);
      expect(find.text('Code porte : A1234'), findsOneWidget);
      expect(
        find.text('Rappel ${formatAppointmentDateTime(_kReminderAt)}'),
        findsOneWidget,
      );
    });

    testWidgets('deux rendez-vous différents affichent des données différentes',
        (tester) async {
      when(() => repository.getPreparation('rdv-2')).thenAnswer(
        (_) async => const Right(AppointmentPreparation(
          address: '3 avenue des Lilas, 75002 Paris',
          items: [PreparationItem(label: 'Carte Vitale', required: true)],
        )),
      );

      await tester.pumpWidget(_wrap(PrepareRdvPage(
        appointmentId: 'rdv-2',
        prefsService: _FakePrefsService(),
        useCase: GetAppointmentPreparationUseCase(repository),
      )));
      await tester.pumpAndSettle();

      expect(find.text('3 avenue des Lilas, 75002 Paris'), findsOneWidget);
      expect(find.byKey(const Key('item_carte_mutuelle')), findsNothing);
    });
  });

  group('PrepareRdvPage — toggle persiste', () {
    testWidgets('tap sur un item le coche et persiste dans le service',
        (tester) async {
      when(() => repository.getPreparation('rdv-1'))
          .thenAnswer((_) async => Right(_kPreparation));
      final prefs = _FakePrefsService();
      await tester.pumpWidget(_wrap(PrepareRdvPage(
        appointmentId: 'rdv-1',
        prefsService: prefs,
        useCase: GetAppointmentPreparationUseCase(repository),
      )));
      await tester.pumpAndSettle();

      // Avant tap : icône non cochée
      expect(
        find.descendant(
          of: find.byKey(const Key('item_carte_vitale')),
          matching: find.byIcon(Icons.check_box),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('item_carte_vitale')));
      await tester.pumpAndSettle();

      // Après tap : icône cochée
      expect(
        find.descendant(
          of: find.byKey(const Key('item_carte_vitale')),
          matching: find.byIcon(Icons.check_box),
        ),
        findsOneWidget,
      );

      // État persisté dans le service
      expect(prefs.checked, contains('carte_vitale'));
    });
  });

  group('PrepareRdvPage — erreur', () {
    testWidgets('affiche un message d\'erreur si l\'API échoue',
        (tester) async {
      when(() => repository.getPreparation('rdv-1')).thenAnswer(
        (_) async => const Left(NotFoundFailure('Rendez-vous introuvable.')),
      );

      await tester.pumpWidget(_wrap(PrepareRdvPage(
        appointmentId: 'rdv-1',
        prefsService: _FakePrefsService(),
        useCase: GetAppointmentPreparationUseCase(repository),
      )));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('prepare_rdv_error')), findsOneWidget);
      expect(find.text('Rendez-vous introuvable.'), findsOneWidget);
    });
  });
}
