import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/dashboard/rail_badges_cubit.dart';
import 'package:app_secretariat/pro_config.dart';

class _MockListWaitingRoom extends Mock implements ListWaitingRoomUseCase {}

class _MockListWaitingList extends Mock implements ListWaitingListUseCase {}

class _MockListQuotes extends Mock implements ListCabinetQuotesUseCase {}

class _MockListConversations extends Mock
    implements ListCabinetConversationsUseCase {}

WaitingRoomEntry _waitingEntry(String id) => WaitingRoomEntry(
      id: id,
      cabinetId: 'cab',
      patientId: 'p-$id',
      patientName: 'Patient $id',
      arrivedAt: DateTime(2026, 1, 1),
    );

WaitingListEntry _waitingListEntry(String id) => WaitingListEntry(
      id: id,
      cabinetId: 'cab',
      patientId: 'p-$id',
      patientName: 'Patient $id',
      motif: '',
      requestedAt: DateTime(2026, 1, 1),
      position: 1,
    );

CabinetQuote _quote(
  String id, {
  required CabinetQuoteStatus status,
  DateTime? expiresAt,
}) =>
    CabinetQuote(
      id: id,
      quoteRef: id,
      cabinetId: 'cab',
      patientId: 'p-$id',
      patientName: 'Patient $id',
      totalCents: 10000,
      patientShareCents: 5000,
      status: status,
      createdAt: DateTime(2026, 1, 1),
      expiresAt: expiresAt,
    );

CabinetConversation _conversation(String id, {required int unreadCount}) =>
    CabinetConversation(
      id: id,
      patientId: 'p-$id',
      patientName: 'Patient $id',
      unreadCount: unreadCount,
    );

void main() {
  group('RailBadgesCubit', () {
    late _MockListWaitingRoom listWaitingRoom;
    late _MockListWaitingList listWaitingList;
    late _MockListQuotes listQuotes;
    late _MockListConversations listConversations;

    setUp(() {
      listWaitingRoom = _MockListWaitingRoom();
      listWaitingList = _MockListWaitingList();
      listQuotes = _MockListQuotes();
      listConversations = _MockListConversations();
    });

    RailBadgesCubit build() => RailBadgesCubit(
          listWaitingRoom: listWaitingRoom,
          listWaitingList: listWaitingList,
          listQuotes: listQuotes,
          listConversations: listConversations,
        );

    blocTest<RailBadgesCubit, RailBadgesState>(
      '#5388 : compteurs réels dérivés des mêmes sources que « À traiter maintenant »',
      build: () {
        final now = DateTime.now();
        when(() => listWaitingRoom()).thenAnswer(
          (_) async => Right([_waitingEntry('w1'), _waitingEntry('w2')]),
        );
        when(() => listWaitingList()).thenAnswer(
          (_) async => Right([_waitingListEntry('l1')]),
        );
        when(() => listQuotes()).thenAnswer(
          (_) async => Right([
            _quote('q1',
                status: CabinetQuoteStatus.sent,
                expiresAt: now.add(const Duration(days: 3))),
            // Signé : jamais compté, même avec une échéance proche.
            _quote('q2',
                status: CabinetQuoteStatus.signed,
                expiresAt: now.add(const Duration(days: 1))),
            // Échéance trop lointaine : hors fenêtre des 7 jours.
            _quote('q3',
                status: CabinetQuoteStatus.sent,
                expiresAt: now.add(const Duration(days: 30))),
          ]),
        );
        when(() => listConversations()).thenAnswer(
          (_) async => Right([
            _conversation('c1', unreadCount: 2),
            _conversation('c2', unreadCount: 1),
          ]),
        );
        return build();
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const RailBadgesState(
          waitingRoomCount: 2,
          waitingListCount: 1,
          expiringQuotesCount: 1,
          unreadMessagesCount: 3,
        ),
      ],
    );

    blocTest<RailBadgesCubit, RailBadgesState>(
      'une source en échec retombe à 0 sans bloquer les autres compteurs',
      build: () {
        when(() => listWaitingRoom())
            .thenAnswer((_) async => const Left(NetworkFailure()));
        when(() => listWaitingList()).thenAnswer(
          (_) async => Right([_waitingListEntry('l1')]),
        );
        when(() => listQuotes()).thenAnswer((_) async => const Right([]));
        when(() => listConversations())
            .thenAnswer((_) async => const Right([]));
        return build();
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const RailBadgesState(waitingRoomCount: 0, waitingListCount: 1),
      ],
    );
  });

  // --- ProConfig.shellConfigFor : injection des badges ------------------------
  group('ProConfig.shellConfigFor — badges (#5388)', () {
    test('les compteurs réels sont injectés sur les bonnes destinations', () {
      final config = ProConfig.shellConfigFor(
        canManageMembers: true,
        canViewAuditLog: true,
        waitingRoomCount: 5,
        waitingListCount: 3,
        expiringQuotesCount: 3,
        unreadMessagesCount: 4,
      );

      int? badgeFor(String route) =>
          config.destinations.firstWhere((d) => d.route == route).badgeCount;

      expect(badgeFor('/salle-attente'), 5);
      expect(badgeFor('/liste-attente'), 3);
      expect(badgeFor('/devis'), 3);
      expect(badgeFor('/messages'), 4);
      // Destination sans compteur associé : pas de badge.
      expect(badgeFor('/agenda'), isNull);
    });

    test('un compteur à 0 (défaut) ne pose aucun badge visible', () {
      final config = ProConfig.shellConfigFor(
        canManageMembers: true,
        canViewAuditLog: true,
      );

      final badged = config.destinations.where(
        (d) => d.badgeCount != null && d.badgeCount! > 0,
      );
      expect(badged, isEmpty);
    });

    test('préserve l\'ordre et le nombre de destinations', () {
      final config = ProConfig.shellConfigFor(
        canManageMembers: true,
        canViewAuditLog: true,
        waitingRoomCount: 5,
      );
      expect(config.destinations.length,
          ProConfig.shellConfig.destinations.length);
      expect(
        config.destinations.map((d) => d.route).toList(),
        ProConfig.shellConfig.destinations.map((d) => d.route).toList(),
      );
    });
  });
}
