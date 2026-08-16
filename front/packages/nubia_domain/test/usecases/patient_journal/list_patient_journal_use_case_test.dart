import 'package:dartz/dartz.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:test/test.dart';

class MockListClinicalSessionsUseCase extends Mock
    implements ListClinicalSessionsUseCase {}

class MockListPrescriptionsUseCase extends Mock
    implements ListPrescriptionsUseCase {}

class MockListCabinetQuotesUseCase extends Mock
    implements ListCabinetQuotesUseCase {}

class MockListPatientDocumentsUseCase extends Mock
    implements ListPatientDocumentsUseCase {}

class MockListCabinetAppointmentsUseCase extends Mock
    implements ListCabinetAppointmentsUseCase {}

void main() {
  const patientId = 'pat-1';

  late MockListClinicalSessionsUseCase listClinicalSessions;
  late MockListPrescriptionsUseCase listPrescriptions;
  late MockListCabinetQuotesUseCase listCabinetQuotes;
  late MockListPatientDocumentsUseCase listPatientDocuments;
  late MockListCabinetAppointmentsUseCase listCabinetAppointments;
  late ListPatientJournalUseCase useCase;

  setUp(() {
    listClinicalSessions = MockListClinicalSessionsUseCase();
    listPrescriptions = MockListPrescriptionsUseCase();
    listCabinetQuotes = MockListCabinetQuotesUseCase();
    listPatientDocuments = MockListPatientDocumentsUseCase();
    listCabinetAppointments = MockListCabinetAppointmentsUseCase();

    useCase = ListPatientJournalUseCase(
      listClinicalSessions: listClinicalSessions,
      listPrescriptions: listPrescriptions,
      listCabinetQuotes: listCabinetQuotes,
      listPatientDocuments: listPatientDocuments,
      listCabinetAppointments: listCabinetAppointments,
    );

    when(() => listClinicalSessions(patientId: patientId))
        .thenAnswer((_) async => const Right([]));
    when(() => listPrescriptions(patientId))
        .thenAnswer((_) async => const Right([]));
    when(() => listCabinetQuotes(
          patientId: patientId,
          limit: 500,
          offset: 0,
        )).thenAnswer((_) async => const Right([]));
    when(() => listPatientDocuments(patientId))
        .thenAnswer((_) async => const Right([]));
    when(() => listCabinetAppointments())
        .thenAnswer((_) async => const Right([]));
  });

  test('fusionne au moins deux sources et trie par date décroissante',
      () async {
    final session = ClinicalSession(
      id: 'session-1',
      appointmentId: 'appt-1',
      status: 'completed',
      startedAt: DateTime.utc(2026, 8, 1),
      practitionerName: 'Dr A. Rousseau',
      acts: const [
        ClinicalAct(
          id: 'act-1',
          ccamCode: 'HBLD038',
          label: 'Détartrage',
          tooth: '26',
          amountCents: 9350,
          createdAt: null,
        ),
      ],
    );
    when(() => listClinicalSessions(patientId: patientId))
        .thenAnswer((_) async => Right([session]));

    final document = PatientDocument(
      id: 'doc-1',
      category: 'radio',
      filename: 'panoramique.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 1024,
      createdAt: DateTime.utc(2026, 8, 11),
    );
    when(() => listPatientDocuments(patientId))
        .thenAnswer((_) async => Right([document]));

    final result = await useCase(patientId);

    final entries = result.getOrElse(() => []);
    expect(entries, hasLength(2));
    expect(entries.map((e) => e.kind), [
      PatientJournalKind.document,
      PatientJournalKind.acte,
    ]);
    expect(entries[0].date.isAfter(entries[1].date), isTrue);
    expect(entries[1].tags, contains('Dent 26'));
    expect(entries[1].amountCents, 9350);
  });

  test(
      'paginate au-delà de la première page de devis quand elle est pleine '
      '(#5572 — sinon les devis les plus anciens du patient sont tronqués)',
      () async {
    CabinetQuote fakeQuote(int i) => CabinetQuote(
          id: 'quote-$i',
          cabinetId: 'cab-1',
          patientId: patientId,
          patientName: 'Marc Dubois',
          totalCents: 100,
          patientShareCents: 100,
          status: CabinetQuoteStatus.draft,
          createdAt: DateTime.utc(2026, 1, 1).add(Duration(days: i)),
        );
    final firstPage = List.generate(500, fakeQuote);
    final secondPage = List.generate(3, (i) => fakeQuote(500 + i));

    when(() => listCabinetQuotes(
          patientId: patientId,
          limit: 500,
          offset: 0,
        )).thenAnswer((_) async => Right(firstPage));
    when(() => listCabinetQuotes(
          patientId: patientId,
          limit: 500,
          offset: 500,
        )).thenAnswer((_) async => Right(secondPage));

    final result = await useCase(patientId);

    final entries = result
        .getOrElse(() => [])
        .where((e) => e.kind == PatientJournalKind.devis);
    expect(entries, hasLength(503));
  });

  test('propage le Failure de la première source en échec', () async {
    when(() => listCabinetQuotes(
          patientId: patientId,
          limit: 500,
          offset: 0,
        )).thenAnswer(
      (_) async => const Left(ServerFailure(message: 'boom')),
    );

    final result = await useCase(patientId);

    expect(result.isLeft(), isTrue);
    result.fold(
      (failure) => expect(failure, isA<ServerFailure>()),
      (_) => fail('doit être un Left'),
    );
  });
}
