import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/nubia_data.dart';
import 'package:nubia_domain/nubia_domain.dart';

PharmacyOrder _order(String id, PharmacyOrderStatus status, int minute) =>
    PharmacyOrder(
      id: id,
      pharmacyId: 'p1',
      prescriptionId: 'rx1',
      status: status,
      createdAt: DateTime.utc(2026, 7, 1),
      updatedAt: DateTime.utc(2026, 7, 1, 10, minute),
    );

void main() {
  test('watchOrders émet au premier poll puis uniquement sur changement',
      () async {
    var call = 0;
    final responses = [
      [_order('o1', PharmacyOrderStatus.received, 0)],
      [
        _order('o1', PharmacyOrderStatus.received, 0)
      ], // identique → pas d'émission
      [_order('o1', PharmacyOrderStatus.preparing, 5)], // changement
    ];
    final events = PollingPharmacyOrderEvents(
      interval: const Duration(milliseconds: 30),
      fetchOrders: () async {
        final index = call < responses.length ? call : responses.length - 1;
        call++;
        return Right(responses[index]);
      },
    );

    final emitted = <List<PharmacyOrder>>[];
    final sub = events.watchOrders().listen(emitted.add);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await sub.cancel();
    events.dispose();

    expect(emitted.length, 2, reason: 'poll identique ne doit pas ré-émettre');
    expect(emitted.first.single.status, PharmacyOrderStatus.received);
    expect(emitted.last.single.status, PharmacyOrderStatus.preparing);
  });

  test('watchOrder émet à chaque changement de statut', () async {
    var call = 0;
    final statuses = [
      PharmacyOrderStatus.preparing,
      PharmacyOrderStatus.ready,
    ];
    final events = PollingPharmacyOrderEvents(
      interval: const Duration(milliseconds: 30),
      fetchOrder: (id) async {
        final index = call < statuses.length ? call : statuses.length - 1;
        call++;
        return Right(_order(id, statuses[index], index));
      },
    );

    final emitted = <PharmacyOrder>[];
    final sub = events.watchOrder('o1').listen(emitted.add);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await sub.cancel();
    events.dispose();

    expect(emitted.length, 2);
    expect(emitted.last.status, PharmacyOrderStatus.ready);
  });

  test('les erreurs de poll sont silencieuses (pas d\'émission, pas de crash)',
      () async {
    final events = PollingPharmacyOrderEvents(
      interval: const Duration(milliseconds: 20),
      fetchOrders: () async => const Left(NetworkFailure()),
    );

    final emitted = <List<PharmacyOrder>>[];
    final sub = events.watchOrders().listen(emitted.add);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await sub.cancel();
    events.dispose();

    expect(emitted, isEmpty);
  });

  test('watch sans fetch correspondant → StateError (erreur de câblage DI)',
      () {
    final events = PollingPharmacyOrderEvents(fetchOrders: () async {
      return const Right([]);
    });
    expect(() => events.watchOrder('o1'), throwsStateError);
    events.dispose();
  });
}
