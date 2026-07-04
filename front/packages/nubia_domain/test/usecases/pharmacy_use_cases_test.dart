import 'package:dartz/dartz.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:test/test.dart';

class MockPharmacyOrdersRepository extends Mock
    implements PharmacyOrdersRepository {}

class MockPatientPharmacyRepository extends Mock
    implements PatientPharmacyRepository {}

class MockPharmacyDirectoryRepository extends Mock
    implements PharmacyDirectoryRepository {}

class MockStockRequestsRepository extends Mock
    implements StockRequestsRepository {}

class MockPrescriptionRepository extends Mock
    implements PrescriptionRepository {}

void main() {
  final order = PharmacyOrder(
    id: 'o1',
    pharmacyId: 'p1',
    prescriptionId: 'rx1',
    status: PharmacyOrderStatus.received,
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 1),
  );

  group('Commandes — vue pharmacie', () {
    late MockPharmacyOrdersRepository repo;

    setUp(() => repo = MockPharmacyOrdersRepository());

    test('ListPharmacyOrdersUseCase délègue le filtre statut au repo',
        () async {
      when(() => repo.list(status: PharmacyOrderStatus.ready))
          .thenAnswer((_) async => Right([order]));

      final result = await ListPharmacyOrdersUseCase(repo)(
        status: PharmacyOrderStatus.ready,
      );

      expect(result.getOrElse(() => []), [order]);
      verify(() => repo.list(status: PharmacyOrderStatus.ready)).called(1);
    });

    test('AcceptPharmacyOrderUseCase propage le Failure du repo', () async {
      when(() => repo.accept('o1')).thenAnswer(
        (_) async => const Left(
          ServerFailure(message: 'Transition invalide.', statusCode: 409),
        ),
      );

      final result = await AcceptPharmacyOrderUseCase(repo)('o1');

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect((failure as ServerFailure).statusCode, 409),
        (_) => fail('doit être un Left'),
      );
    });

    test('ConfirmPharmacyPickupUseCase passe le token opaque au repo',
        () async {
      when(() => repo.confirmPickup('tok-123'))
          .thenAnswer((_) async => Right(order));

      final result = await ConfirmPharmacyPickupUseCase(repo)('tok-123');

      expect(result.isRight(), isTrue);
      verify(() => repo.confirmPickup('tok-123')).called(1);
    });

    test('RejectPharmacyOrderUseCase transmet le motif', () async {
      when(() => repo.reject('o1', 'Produit indisponible'))
          .thenAnswer((_) async => Right(order));

      await RejectPharmacyOrderUseCase(repo)('o1', 'Produit indisponible');

      verify(() => repo.reject('o1', 'Produit indisponible')).called(1);
    });
  });

  group('Commandes — vue patient', () {
    late MockPatientPharmacyRepository repo;

    setUp(() => repo = MockPatientPharmacyRepository());

    test('CreatePharmacyOrderUseCase délègue prescriptionId + pharmacyId',
        () async {
      when(() => repo.createOrder(prescriptionId: 'rx1', pharmacyId: 'p1'))
          .thenAnswer((_) async => Right(order));

      final result = await CreatePharmacyOrderUseCase(repo)(
        prescriptionId: 'rx1',
        pharmacyId: 'p1',
      );

      expect(result.isRight(), isTrue);
      verify(() => repo.createOrder(prescriptionId: 'rx1', pharmacyId: 'p1'))
          .called(1);
    });

    test('GetPickupTokenUseCase renvoie le token du QR', () async {
      when(() => repo.getPickupToken('o1'))
          .thenAnswer((_) async => const Right('tok-abc'));

      final result = await GetPickupTokenUseCase(repo)('o1');

      expect(result.getOrElse(() => ''), 'tok-abc');
    });

    test('GetMyPharmacyUseCase supporte l\'absence de pharmacie déclarée',
        () async {
      when(() => repo.getMyPharmacy())
          .thenAnswer((_) async => const Right(null));

      final result = await GetMyPharmacyUseCase(repo)();

      expect(result.isRight(), isTrue);
      result.fold((_) => fail('doit être un Right'), (p) => expect(p, isNull));
    });
  });

  group('Annuaire', () {
    test('SearchPharmaciesUseCase délègue les filtres géo', () async {
      final repo = MockPharmacyDirectoryRepository();
      const pharmacy = Pharmacy(id: 'p1', name: 'Pharmacie du Port');
      when(() => repo.search(query: 'port', lat: 48.86, lng: 2.35, radiusKm: 5))
          .thenAnswer((_) async => const Right([pharmacy]));

      final result = await SearchPharmaciesUseCase(repo)(
        query: 'port',
        lat: 48.86,
        lng: 2.35,
        radiusKm: 5,
      );

      expect(result.getOrElse(() => []), [pharmacy]);
    });
  });

  group('Stock', () {
    test('RespondStockRequestUseCase route accept/reject/fulfill', () async {
      final repo = MockStockRequestsRepository();
      final request = StockRequest(
        id: 's1',
        pharmacyId: 'p1',
        items: const [StockRequestItem(label: 'Compresses', quantity: 10)],
        status: StockRequestStatus.sent,
        createdAt: DateTime.utc(2026, 7, 1),
      );
      when(() => repo.accept('s1')).thenAnswer((_) async => Right(request));
      when(() => repo.reject('s1', note: 'rupture'))
          .thenAnswer((_) async => Right(request));
      when(() => repo.fulfill('s1')).thenAnswer((_) async => Right(request));

      final useCase = RespondStockRequestUseCase(repo);
      await useCase('s1', StockRequestResponse.accept);
      await useCase('s1', StockRequestResponse.reject, note: 'rupture');
      await useCase('s1', StockRequestResponse.fulfill);

      verify(() => repo.accept('s1')).called(1);
      verify(() => repo.reject('s1', note: 'rupture')).called(1);
      verify(() => repo.fulfill('s1')).called(1);
    });
  });

  group('Ordonnance — praticien', () {
    test('SendPrescriptionToPharmacyUseCase délègue au repo prescription',
        () async {
      final repo = MockPrescriptionRepository();
      final prescription = Prescription(
        id: 'rx1',
        patientId: 'pat1',
        items: const [],
        status: PrescriptionStatus.sent,
        createdAt: DateTime.utc(2026, 7, 1),
      );
      when(() => repo.sendToPharmacy(prescriptionId: 'rx1', pharmacyId: 'p1'))
          .thenAnswer((_) async => Right(prescription));

      final result = await SendPrescriptionToPharmacyUseCase(repo)(
        prescriptionId: 'rx1',
        pharmacyId: 'p1',
      );

      result.fold(
        (_) => fail('doit être un Right'),
        (p) => expect(p.status, PrescriptionStatus.sent),
      );
    });
  });
}
