//! Tests : `MaintenanceBloc`/`MaintenancePage` (#7166/#7167, DP-F18) —
//! chargement des compteurs/tickets/équipements, création de ticket avec et
//! sans photo (upload puis rattachement), rendu de l'écran (squelette/vide/
//! erreur/liste).

import 'dart:convert';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_secretariat/features/maintenance/maintenance_bloc.dart';
import 'package:app_secretariat/features/maintenance/maintenance_event.dart';
import 'package:app_secretariat/features/maintenance/maintenance_page.dart';
import 'package:app_secretariat/features/maintenance/maintenance_state.dart';

class _FakeFailure extends Failure {
  const _FakeFailure(super.message);
}

class MockGetMaintenanceStatsUseCase extends Mock
    implements GetMaintenanceStatsUseCase {}

class MockListEquipmentUseCase extends Mock implements ListEquipmentUseCase {}

class MockListMaintenanceTicketsUseCase extends Mock
    implements ListMaintenanceTicketsUseCase {}

class MockCreateMaintenanceTicketUseCase extends Mock
    implements CreateMaintenanceTicketUseCase {}

class MockUploadMaintenancePhotoUseCase extends Mock
    implements UploadMaintenancePhotoUseCase {}

class MockFilePickerService extends Mock implements FilePickerService {}

class MockMaintenanceBloc extends MockBloc<MaintenanceEvent, MaintenanceState>
    implements MaintenanceBloc {}

/// PNG 1×1 valide (pas juste des octets arbitraires) — `Image.memory` dans
/// l'aperçu du dialogue de création décode réellement le contenu.
Uint8List _onePixelPng() => base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
      '42YAAAAASUVORK5CYII=',
    );

const _stats = MaintenanceStats(
  openTickets: 2,
  plannedChecks: 3,
  overdueChecks: 1,
);

const _equipment = Equipment(
  id: 'equip-1',
  label: 'Autoclave',
  category: 'Stérilisation',
  room: 'Salle 2',
  createdAt: '2026-01-01T09:00:00Z',
);

const _ticket = MaintenanceTicket(
  id: 'ticket-1',
  equipmentId: 'equip-1',
  title: 'Fuite eau autoclave',
  priority: 'high',
  status: 'open',
  reportedBy: 'user-1',
  createdAt: '2026-01-02T09:00:00Z',
);

MaintenanceBloc _buildBloc({
  MockGetMaintenanceStatsUseCase? getStats,
  MockListEquipmentUseCase? listEquipment,
  MockListMaintenanceTicketsUseCase? listTickets,
  MockCreateMaintenanceTicketUseCase? createTicket,
  MockUploadMaintenancePhotoUseCase? uploadPhoto,
}) =>
    MaintenanceBloc(
      getStats: getStats ?? MockGetMaintenanceStatsUseCase(),
      listEquipment: listEquipment ?? MockListEquipmentUseCase(),
      listTickets: listTickets ?? MockListMaintenanceTicketsUseCase(),
      createTicket: createTicket ?? MockCreateMaintenanceTicketUseCase(),
      uploadPhoto: uploadPhoto ?? MockUploadMaintenancePhotoUseCase(),
    );

void main() {
  group('MaintenanceBloc', () {
    blocTest<MaintenanceBloc, MaintenanceState>(
      'MaintenanceLoadRequested réussi émet Loading puis Loaded',
      build: () {
        final getStats = MockGetMaintenanceStatsUseCase();
        final listEquipment = MockListEquipmentUseCase();
        final listTickets = MockListMaintenanceTicketsUseCase();
        when(() => getStats()).thenAnswer((_) async => const Right(_stats));
        when(() => listEquipment())
            .thenAnswer((_) async => const Right([_equipment]));
        when(() => listTickets())
            .thenAnswer((_) async => const Right([_ticket]));
        return _buildBloc(
          getStats: getStats,
          listEquipment: listEquipment,
          listTickets: listTickets,
        );
      },
      act: (bloc) => bloc.add(const MaintenanceLoadRequested()),
      expect: () => [
        const MaintenanceLoading(),
        const MaintenanceLoaded(
          stats: _stats,
          tickets: [_ticket],
          equipment: [_equipment],
        ),
      ],
    );

    blocTest<MaintenanceBloc, MaintenanceState>(
      'MaintenanceLoadRequested en échec émet Loading puis Error',
      build: () {
        final getStats = MockGetMaintenanceStatsUseCase();
        final listEquipment = MockListEquipmentUseCase();
        final listTickets = MockListMaintenanceTicketsUseCase();
        when(() => getStats())
            .thenAnswer((_) async => const Left(_FakeFailure('Erreur réseau')));
        when(() => listEquipment())
            .thenAnswer((_) async => const Right([_equipment]));
        when(() => listTickets())
            .thenAnswer((_) async => const Right([_ticket]));
        return _buildBloc(
          getStats: getStats,
          listEquipment: listEquipment,
          listTickets: listTickets,
        );
      },
      act: (bloc) => bloc.add(const MaintenanceLoadRequested()),
      expect: () => [
        const MaintenanceLoading(),
        const MaintenanceError('Erreur réseau'),
      ],
    );

    blocTest<MaintenanceBloc, MaintenanceState>(
      'MaintenanceTicketCreateRequested sans photo crée le ticket et '
      'incrémente le compteur de tickets ouverts',
      build: () {
        final createTicket = MockCreateMaintenanceTicketUseCase();
        when(() => createTicket(
              equipmentId: any(named: 'equipmentId'),
              title: any(named: 'title'),
              description: any(named: 'description'),
              priority: any(named: 'priority'),
              assignedToEmail: any(named: 'assignedToEmail'),
              photoDocumentIds: any(named: 'photoDocumentIds'),
            )).thenAnswer((_) async => const Right(_ticket));
        return _buildBloc(createTicket: createTicket);
      },
      seed: () => const MaintenanceLoaded(
        stats: _stats,
        tickets: [],
        equipment: [_equipment],
      ),
      act: (bloc) => bloc.add(const MaintenanceTicketCreateRequested(
        equipmentId: 'equip-1',
        title: 'Fuite eau autoclave',
      )),
      expect: () => [
        const MaintenanceLoaded(
          stats: _stats,
          tickets: [],
          equipment: [_equipment],
          creating: true,
        ),
        const MaintenanceLoaded(
          stats: MaintenanceStats(
            openTickets: 3,
            plannedChecks: 3,
            overdueChecks: 1,
          ),
          tickets: [_ticket],
          equipment: [_equipment],
        ),
      ],
    );

    final photoTicketCreateUseCase = MockCreateMaintenanceTicketUseCase();
    blocTest<MaintenanceBloc, MaintenanceState>(
      'MaintenanceTicketCreateRequested avec photo uploade la photo puis '
      'crée le ticket en la référençant',
      build: () {
        final uploadPhoto = MockUploadMaintenancePhotoUseCase();
        final createTicket = photoTicketCreateUseCase;
        when(() => uploadPhoto(
              bytes: any(named: 'bytes'),
              filename: any(named: 'filename'),
              mimeType: any(named: 'mimeType'),
            )).thenAnswer((_) async => const Right('doc-1'));
        when(() => createTicket(
              equipmentId: any(named: 'equipmentId'),
              title: any(named: 'title'),
              description: any(named: 'description'),
              priority: any(named: 'priority'),
              assignedToEmail: any(named: 'assignedToEmail'),
              photoDocumentIds: any(named: 'photoDocumentIds'),
            )).thenAnswer((_) async => const Right(_ticket));
        return _buildBloc(uploadPhoto: uploadPhoto, createTicket: createTicket);
      },
      seed: () => const MaintenanceLoaded(
        stats: _stats,
        tickets: [],
        equipment: [_equipment],
      ),
      act: (bloc) => bloc.add(MaintenanceTicketCreateRequested(
        equipmentId: 'equip-1',
        title: 'Fuite eau autoclave',
        photo: PickedFile(
          path: null,
          name: 'photo.jpg',
          mimeType: 'image/jpeg',
          bytes: _onePixelPng(),
        ),
      )),
      expect: () => [
        const MaintenanceLoaded(
          stats: _stats,
          tickets: [],
          equipment: [_equipment],
          creating: true,
        ),
        const MaintenanceLoaded(
          stats: MaintenanceStats(
            openTickets: 3,
            plannedChecks: 3,
            overdueChecks: 1,
          ),
          tickets: [_ticket],
          equipment: [_equipment],
        ),
      ],
      verify: (_) {
        final captured = verify(() => photoTicketCreateUseCase(
              equipmentId: any(named: 'equipmentId'),
              title: any(named: 'title'),
              description: any(named: 'description'),
              priority: any(named: 'priority'),
              assignedToEmail: any(named: 'assignedToEmail'),
              photoDocumentIds: captureAny(named: 'photoDocumentIds'),
            )).captured;
        expect(captured.single, ['doc-1']);
      },
    );
  });

  group('MaintenancePage (widget)', () {
    late MockFilePickerService filePicker;

    setUp(() {
      filePicker = MockFilePickerService();
      GetIt.instance.registerFactory<FilePickerService>(() => filePicker);
      addTearDown(GetIt.instance.reset);
    });

    testWidgets('affiche un squelette pendant le chargement', (tester) async {
      final bloc = MockMaintenanceBloc();
      when(() => bloc.state).thenReturn(const MaintenanceLoading());
      await tester.pumpApp(
        BlocProvider<MaintenanceBloc>.value(
          value: bloc,
          child: const MaintenancePage(),
        ),
      );

      expect(find.byKey(const Key('maintenance_loading')), findsOneWidget);
    });

    testWidgets('affiche une erreur avec bouton réessayer', (tester) async {
      final bloc = MockMaintenanceBloc();
      when(() => bloc.state)
          .thenReturn(const MaintenanceError('Erreur réseau'));
      await tester.pumpApp(
        BlocProvider<MaintenanceBloc>.value(
          value: bloc,
          child: const MaintenancePage(),
        ),
      );

      expect(find.byKey(const Key('maintenance_error')), findsOneWidget);
    });

    testWidgets(
        'affiche les compteurs, les tickets et les équipements chargés',
        (tester) async {
      final bloc = MockMaintenanceBloc();
      when(() => bloc.state).thenReturn(const MaintenanceLoaded(
        stats: _stats,
        tickets: [_ticket],
        equipment: [_equipment],
      ));
      await tester.pumpApp(
        BlocProvider<MaintenanceBloc>.value(
          value: bloc,
          child: const MaintenancePage(),
        ),
      );

      expect(find.byKey(const Key('maintenance_kpi_bar')), findsOneWidget);
      expect(find.byKey(const Key('maintenance_ticket_ticket-1')),
          findsOneWidget);
      expect(find.byKey(const Key('equipment_equip-1')), findsOneWidget);
      expect(find.text('Fuite eau autoclave'), findsOneWidget);
      expect(find.text('Autoclave'), findsOneWidget);
    });

    testWidgets(
        'créer un ticket avec photo dispatch MaintenanceTicketCreateRequested',
        (tester) async {
      // Surface agrandie : le formulaire (titre/description/équipement/
      // priorité/e-mail/photo) déborde la hauteur par défaut (600px) du
      // banc de test, ce qui fait échouer silencieusement les `tap()` sur
      // les champs en bas du dialogue (widget hors zone visible).
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;

      final bloc = MockMaintenanceBloc();
      when(() => bloc.state).thenReturn(const MaintenanceLoaded(
        stats: _stats,
        tickets: [],
        equipment: [_equipment],
      ));
      final picked = PickedFile(
        path: null,
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        bytes: _onePixelPng(),
      );
      when(() => filePicker.pickFile(allowedExtensions: ['jpg', 'jpeg', 'png']))
          .thenAnswer((_) async => picked);

      await tester.pumpApp(
        BlocProvider<MaintenanceBloc>.value(
          value: bloc,
          child: const MaintenancePage(),
        ),
      );

      await tester.tap(find.byKey(const Key('maintenance_new_ticket_fab')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('maintenance_ticket_title')),
        'Fuite eau autoclave',
      );
      final pickPhotoButton =
          find.byKey(const Key('maintenance_ticket_pick_photo'));
      await tester.ensureVisible(pickPhotoButton);
      await tester.pumpAndSettle();
      await tester.tap(pickPhotoButton);
      await tester.pumpAndSettle();

      final confirmButton =
          find.byKey(const Key('confirm_create_maintenance_ticket_button'));
      await tester.ensureVisible(confirmButton);
      await tester.pumpAndSettle();
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      // Même instance `picked` des deux côtés (le sélecteur mocké la renvoie
      // telle quelle) : l'égalité `Equatable` de l'événement peut donc
      // comparer `photo` malgré l'absence d'`==` sur `PickedFile`.
      verify(() => bloc.add(MaintenanceTicketCreateRequested(
            title: 'Fuite eau autoclave',
            priority: 'medium',
            photo: picked,
          ))).called(1);
    });
  });
}
