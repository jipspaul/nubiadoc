import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/patient_journal_entry.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/usecases/cabinet_appointments/list_cabinet_appointments_use_case.dart';
import 'package:nubia_domain/src/usecases/cabinet_quotes/list_cabinet_quotes_use_case.dart';
import 'package:nubia_domain/src/usecases/clinical/list_clinical_sessions_use_case.dart';
import 'package:nubia_domain/src/usecases/patient_documents/list_patient_documents_use_case.dart';
import 'package:nubia_domain/src/usecases/prescription/list_prescriptions_use_case.dart';

/// Agrège les cinq sources du dossier patient (actes, ordonnances, devis,
/// documents, rendez-vous) en une seule chronologie triée par date
/// décroissante (#4970 — « un journal, pas cinq sections »). Compose les
/// usecases sources existants, ne les remplace pas.
class ListPatientJournalUseCase {
  final ListClinicalSessionsUseCase _listClinicalSessions;
  final ListPrescriptionsUseCase _listPrescriptions;
  final ListCabinetQuotesUseCase _listCabinetQuotes;
  final ListPatientDocumentsUseCase _listPatientDocuments;
  final ListCabinetAppointmentsUseCase _listCabinetAppointments;

  const ListPatientJournalUseCase({
    required ListClinicalSessionsUseCase listClinicalSessions,
    required ListPrescriptionsUseCase listPrescriptions,
    required ListCabinetQuotesUseCase listCabinetQuotes,
    required ListPatientDocumentsUseCase listPatientDocuments,
    required ListCabinetAppointmentsUseCase listCabinetAppointments,
  })  : _listClinicalSessions = listClinicalSessions,
        _listPrescriptions = listPrescriptions,
        _listCabinetQuotes = listCabinetQuotes,
        _listPatientDocuments = listPatientDocuments,
        _listCabinetAppointments = listCabinetAppointments;

  Future<Either<Failure, List<PatientJournalEntry>>> call(
    String patientId,
  ) async {
    final sessionsResult = await _listClinicalSessions(patientId: patientId);
    final prescriptionsResult = await _listPrescriptions(patientId);
    final quotesResult = await _listCabinetQuotes();
    final documentsResult = await _listPatientDocuments(patientId);
    final appointmentsResult = await _listCabinetAppointments();

    final failure = _firstFailure(sessionsResult) ??
        _firstFailure(prescriptionsResult) ??
        _firstFailure(quotesResult) ??
        _firstFailure(documentsResult) ??
        _firstFailure(appointmentsResult);
    if (failure != null) return Left(failure);

    final entries = <PatientJournalEntry>[
      ...sessionsResult.fold((_) => const [], (sessions) => sessions
          .expand((session) => session.acts.map((act) {
                final date = act.createdAt ?? session.startedAt;
                if (date == null) return null;
                final tags = <String>[
                  if (act.tooth != null) 'Dent ${act.tooth}',
                  if (session.practitionerName != null)
                    session.practitionerName!,
                ];
                return PatientJournalEntry(
                  date: date,
                  kind: PatientJournalKind.acte,
                  title: act.label,
                  subtitle: act.ccamCode,
                  tags: tags,
                  amountCents: act.amountCents,
                );
              }))
          .whereType<PatientJournalEntry>()),
      ...prescriptionsResult.fold(
        (_) => const [],
        (prescriptions) => prescriptions.map((prescription) {
          return PatientJournalEntry(
            date: prescription.createdAt,
            kind: PatientJournalKind.ordonnance,
            title: 'Ordonnance',
            subtitle: prescription.items.isEmpty
                ? null
                : prescription.items.first.label,
            tags: ['${prescription.items.length} ligne(s)'],
          );
        }),
      ),
      ...quotesResult.fold(
        (_) => const [],
        (quotes) => quotes
            .where((quote) => quote.patientId == patientId)
            .map((quote) {
          return PatientJournalEntry(
            date: quote.createdAt,
            kind: PatientJournalKind.devis,
            title: 'Devis',
            subtitle: quote.patientName,
            tags: [quote.status.name],
            amountCents: quote.totalCents,
          );
        }),
      ),
      ...documentsResult.fold(
        (_) => const [],
        (documents) => documents.map((document) {
          return PatientJournalEntry(
            date: document.createdAt,
            kind: PatientJournalKind.document,
            title: document.filename,
            subtitle: document.category,
            tags: [document.category],
          );
        }),
      ),
      ...appointmentsResult.fold(
        (_) => const [],
        (appointments) => appointments
            .where((appointment) => appointment.patientId == patientId)
            .map((appointment) {
          return PatientJournalEntry(
            date: appointment.startsAt,
            kind: PatientJournalKind.rendezVous,
            title: appointment.motif,
            subtitle: appointment.practitionerName,
            tags: [appointment.status.name],
          );
        }),
      ),
    ];

    entries.sort((a, b) => b.date.compareTo(a.date));
    return Right(entries);
  }

  Failure? _firstFailure<T>(Either<Failure, T> result) =>
      result.fold((failure) => failure, (_) => null);
}
