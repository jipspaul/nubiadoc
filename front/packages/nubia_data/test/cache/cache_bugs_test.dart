import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/src/entities/appointment.dart';
import 'package:nubia_domain/src/repositories/appointment_repository.dart';

import 'package:nubia_data/src/cache/appointments_cache.dart';
import 'package:nubia_data/src/cache/cached_data.dart';
import 'package:nubia_data/src/repositories/cached_appointments_repository_impl.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockAppointmentRepository extends Mock implements AppointmentRepository {}

class MockAppointmentsCache extends Mock implements AppointmentsCache {}

// Pure-Dart fake — separate buckets for list vs single (mirrors composite PK).
class FakeAppointmentsCache implements AppointmentsCache {
  final Map<String, Appointment> _singles = {};
  List<Appointment>? _upcoming;

  @override
  Future<CachedData<List<Appointment>>?> getUpcoming() async {
    if (_upcoming == null) return null;
    return CachedData(data: List.of(_upcoming!), cachedAt: DateTime(2026));
  }

  @override
  Future<CachedData<Appointment>?> getById(String id) async {
    final a = _singles[id];
    if (a == null) return null;
    return CachedData(data: a, cachedAt: DateTime(2026));
  }

  @override
  Future<void> saveUpcoming(List<Appointment> appointments) async =>
      _upcoming = List.of(appointments);

  @override
  Future<void> saveOne(Appointment appointment) async =>
      _singles[appointment.id] = appointment;

  @override
  Future<void> remove(String id) async => _singles.remove(id);

  @override
  Future<void> clear() async {
    _singles.clear();
    _upcoming = null;
  }

  @override
  Future<void> clearUpcoming() async => _upcoming = null;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _appt1 = Appointment(
  id: 'appt-1',
  cabinetId: 'cab-1',
  practitionerName: 'Dr Dupont',
  practitionerSpecialty: 'Dentiste',
  startsAt: DateTime(2026, 8, 1, 10),
  duration: const Duration(minutes: 30),
  motif: 'Détartrage',
  status: AppointmentStatus.confirmed,
);

final _appt2 = Appointment(
  id: 'appt-2',
  cabinetId: 'cab-1',
  practitionerName: 'Dr Martin',
  practitionerSpecialty: 'Chirurgien',
  startsAt: DateTime(2026, 8, 5, 14),
  duration: const Duration(minutes: 45),
  motif: 'Extraction',
  status: AppointmentStatus.confirmed,
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(_appt1);
    registerFallbackValue(<Appointment>[]);
  });

  // -------------------------------------------------------------------------
  // T1 — composite-key alias : saveOne ne doit pas écraser les entrées de list
  // -------------------------------------------------------------------------
  group('T1 — AppointmentsCache : saveOne ne vide pas la liste upcoming', () {
    late FakeAppointmentsCache cache;

    setUp(() => cache = FakeAppointmentsCache());

    test(
        'saveUpcoming([a1,a2]) puis saveOne(a1) → getUpcoming retourne toujours [a1,a2]',
        () async {
      await cache.saveUpcoming([_appt1, _appt2]);

      // saveOne with same id as a list item — must NOT clobber the list bucket
      await cache.saveOne(_appt1);

      final result = await cache.getUpcoming();
      expect(result, isNotNull);
      expect(
          result!.data.map((a) => a.id).toSet(), equals({'appt-1', 'appt-2'}));
    });
  });

  // -------------------------------------------------------------------------
  // T2 — success→exception : cache write throw ne doit pas masquer Right
  // -------------------------------------------------------------------------
  group('T2 — cacheFirst : cache write throw préserve Right(data)', () {
    late MockAppointmentRepository mockRemote;
    late MockAppointmentsCache mockCache;
    late CachedAppointmentsRepositoryImpl repo;

    setUp(() {
      mockRemote = MockAppointmentRepository();
      mockCache = MockAppointmentsCache();
      repo = CachedAppointmentsRepositoryImpl(
        remote: mockRemote,
        cache: mockCache,
      );
    });

    test('remote réussit + saveUpcoming throw → résultat reste Right(data)',
        () async {
      when(() => mockCache.getUpcoming()).thenAnswer((_) async => null);
      when(() => mockRemote.getUpcoming())
          .thenAnswer((_) async => Right([_appt1]));
      when(() => mockCache.saveUpcoming(any()))
          .thenThrow(Exception('disk full'));

      final result = await repo.getUpcoming();

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('attendu Right'),
        (list) => expect(list, equals([_appt1])),
      );
    });
  });

  // -------------------------------------------------------------------------
  // T3 — book invalide la liste upcoming
  // -------------------------------------------------------------------------
  group('T3 — book/checkin : invalide la liste cached upcoming', () {
    late MockAppointmentRepository mockRemote;
    late MockAppointmentsCache mockCache;
    late CachedAppointmentsRepositoryImpl repo;

    setUp(() {
      mockRemote = MockAppointmentRepository();
      mockCache = MockAppointmentsCache();
      repo = CachedAppointmentsRepositoryImpl(
        remote: mockRemote,
        cache: mockCache,
      );
    });

    test('book réussi → saveOne ET clearUpcoming appelés', () async {
      when(() => mockRemote.book(slotId: 'slot-2', motif: 'Extraction'))
          .thenAnswer((_) async => Right(_appt2));
      when(() => mockCache.saveOne(any())).thenAnswer((_) async {});
      when(() => mockCache.clearUpcoming()).thenAnswer((_) async {});

      final result = await repo.book(slotId: 'slot-2', motif: 'Extraction');

      expect(result.isRight(), isTrue);
      verify(() => mockCache.saveOne(_appt2)).called(1);
      verify(() => mockCache.clearUpcoming()).called(1);
    });

    test('checkin réussi → saveOne ET clearUpcoming appelés', () async {
      when(() => mockRemote.checkin('appt-1'))
          .thenAnswer((_) async => Right(_appt1));
      when(() => mockCache.saveOne(any())).thenAnswer((_) async {});
      when(() => mockCache.clearUpcoming()).thenAnswer((_) async {});

      await repo.checkin('appt-1');

      verify(() => mockCache.saveOne(_appt1)).called(1);
      verify(() => mockCache.clearUpcoming()).called(1);
    });
  });

  // -------------------------------------------------------------------------
  // T4 — cancel/modify : dead saveOne supprimé
  // -------------------------------------------------------------------------
  group('T4 — cancel/modify : saveOne mort supprimé', () {
    late MockAppointmentRepository mockRemote;
    late MockAppointmentsCache mockCache;
    late CachedAppointmentsRepositoryImpl repo;

    setUp(() {
      mockRemote = MockAppointmentRepository();
      mockCache = MockAppointmentsCache();
      repo = CachedAppointmentsRepositoryImpl(
        remote: mockRemote,
        cache: mockCache,
      );
    });

    test('cancel réussi → clear appelé, saveOne jamais appelé', () async {
      final cancelled = Appointment(
        id: 'appt-1',
        cabinetId: 'cab-1',
        practitionerName: 'Dr Dupont',
        practitionerSpecialty: 'Dentiste',
        startsAt: DateTime(2026, 8, 1, 10),
        duration: const Duration(minutes: 30),
        motif: 'Détartrage',
        status: AppointmentStatus.cancelled,
      );

      when(() => mockRemote.cancel('appt-1'))
          .thenAnswer((_) async => Right(cancelled));
      when(() => mockCache.clear()).thenAnswer((_) async {});

      await repo.cancel('appt-1');

      verify(() => mockCache.clear()).called(1);
      verifyNever(() => mockCache.saveOne(any()));
    });

    test('modify réussi → clear appelé, saveOne jamais appelé', () async {
      when(() => mockRemote.modify(id: 'appt-1', newSlotId: 'slot-99'))
          .thenAnswer((_) async => Right(_appt1));
      when(() => mockCache.clear()).thenAnswer((_) async {});

      await repo.modify(id: 'appt-1', newSlotId: 'slot-99');

      verify(() => mockCache.clear()).called(1);
      verifyNever(() => mockCache.saveOne(any()));
    });
  });
}
