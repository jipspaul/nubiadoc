import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/src/entities/appointment.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/appointment_repository.dart';

import 'package:nubia_data/src/cache/appointments_cache.dart';
import 'package:nubia_data/src/cache/cached_data.dart';
import 'package:nubia_data/src/repositories/cached_appointments_repository_impl.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockAppointmentRepository extends Mock implements AppointmentRepository {}

class MockAppointmentsCache extends Mock implements AppointmentsCache {}

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
// Helpers
// ---------------------------------------------------------------------------

List<Appointment> _rightList(Either<Failure, List<Appointment>> r) =>
    r.fold((l) => throw AssertionError('expected Right, got $l'), (v) => v);

Appointment _rightOne(Either<Failure, Appointment> r) =>
    r.fold((l) => throw AssertionError('expected Right, got $l'), (v) => v);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(_appt1);
    registerFallbackValue(<Appointment>[]);
  });

  late MockAppointmentRepository mockRemote;
  late MockAppointmentsCache mockCache;
  late CachedAppointmentsRepositoryImpl repo;

  setUp(() {
    mockRemote = MockAppointmentRepository();
    mockCache = MockAppointmentsCache();
    repo = CachedAppointmentsRepositoryImpl(
      remote: mockRemote,
      cache: mockCache,
      maxAge: const Duration(minutes: 5),
    );
  });

  group('getUpcoming — cache-hit (données fraîches)', () {
    test('retourne les données du cache sans appeler le remote', () async {
      final freshCache = CachedData(
        data: [_appt1, _appt2],
        cachedAt: DateTime.now(),
      );

      when(() => mockCache.getUpcoming())
          .thenAnswer((_) async => freshCache);

      final result = await repo.getUpcoming();

      expect(result.isRight(), isTrue);
      expect(_rightList(result), equals([_appt1, _appt2]));
      verifyNever(() => mockRemote.getUpcoming());
    });
  });

  group('getUpcoming — cache-miss (cache vide ou stale)', () {
    test('appelle le remote quand le cache est vide, puis met le cache à jour',
        () async {
      when(() => mockCache.getUpcoming()).thenAnswer((_) async => null);
      when(() => mockRemote.getUpcoming())
          .thenAnswer((_) async => Right([_appt1]));
      when(() => mockCache.saveUpcoming(any())).thenAnswer((_) async {});

      final result = await repo.getUpcoming();

      expect(result.isRight(), isTrue);
      expect(_rightList(result), equals([_appt1]));
      verify(() => mockRemote.getUpcoming()).called(1);
      verify(() => mockCache.saveUpcoming([_appt1])).called(1);
    });

    test('appelle le remote quand le cache est stale, puis met le cache à jour',
        () async {
      final staleCache = CachedData(
        data: [_appt2],
        cachedAt: DateTime.now().subtract(const Duration(minutes: 10)),
      );

      when(() => mockCache.getUpcoming())
          .thenAnswer((_) async => staleCache);
      when(() => mockRemote.getUpcoming())
          .thenAnswer((_) async => Right([_appt1, _appt2]));
      when(() => mockCache.saveUpcoming(any())).thenAnswer((_) async {});

      final result = await repo.getUpcoming();

      expect(result.isRight(), isTrue);
      expect(_rightList(result), equals([_appt1, _appt2]));
      verify(() => mockRemote.getUpcoming()).called(1);
      verify(() => mockCache.saveUpcoming([_appt1, _appt2])).called(1);
    });

    test('ne met pas à jour le cache quand le remote échoue', () async {
      when(() => mockCache.getUpcoming()).thenAnswer((_) async => null);
      when(() => mockRemote.getUpcoming())
          .thenAnswer((_) async => const Left(OfflineFailure()));

      final result = await repo.getUpcoming();

      expect(result.isLeft(), isTrue);
      verifyNever(() => mockCache.saveUpcoming(any()));
    });
  });

  group('getById — cache-hit', () {
    test('retourne le RDV depuis le cache sans appeler le remote', () async {
      final freshCache = CachedData(
        data: _appt1,
        cachedAt: DateTime.now(),
      );

      when(() => mockCache.getById('appt-1'))
          .thenAnswer((_) async => freshCache);

      final result = await repo.getById('appt-1');

      expect(result.isRight(), isTrue);
      expect(_rightOne(result), equals(_appt1));
      verifyNever(() => mockRemote.getById(any()));
    });
  });

  group('getById — cache-miss', () {
    test('appelle le remote puis met le cache à jour', () async {
      when(() => mockCache.getById('appt-1')).thenAnswer((_) async => null);
      when(() => mockRemote.getById('appt-1'))
          .thenAnswer((_) async => Right(_appt1));
      when(() => mockCache.saveOne(any())).thenAnswer((_) async {});

      final result = await repo.getById('appt-1');

      expect(result.isRight(), isTrue);
      expect(_rightOne(result), equals(_appt1));
      verify(() => mockRemote.getById('appt-1')).called(1);
      verify(() => mockCache.saveOne(_appt1)).called(1);
    });
  });

  group('book — write-through', () {
    test('délègue au remote et met le RDV en cache', () async {
      when(() => mockRemote.book(slotId: 'slot-1', motif: 'Détartrage'))
          .thenAnswer((_) async => Right(_appt1));
      when(() => mockCache.saveOne(any())).thenAnswer((_) async {});

      final result = await repo.book(slotId: 'slot-1', motif: 'Détartrage');

      expect(result.isRight(), isTrue);
      expect(_rightOne(result), equals(_appt1));
      verify(() => mockCache.saveOne(_appt1)).called(1);
    });
  });

  group('cancel — write-through + invalidation', () {
    test('délègue au remote, met à jour le cache et invalide la liste',
        () async {
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
      when(() => mockCache.saveOne(any())).thenAnswer((_) async {});
      when(() => mockCache.clear()).thenAnswer((_) async {});

      final result = await repo.cancel('appt-1');

      expect(result.isRight(), isTrue);
      expect(_rightOne(result), equals(cancelled));
      verify(() => mockCache.saveOne(cancelled)).called(1);
      verify(() => mockCache.clear()).called(1);
    });
  });
}
