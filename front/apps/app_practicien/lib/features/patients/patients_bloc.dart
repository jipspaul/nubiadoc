import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'patients_event.dart';
import 'patients_state.dart';

class PatientsBloc extends Bloc<PatientsEvent, PatientsState>
    with SafeEmitMixin<PatientsState> {
  final ListCabinetPatientsUseCase _list;
  final GetCabinetPatientUseCase _getById;
  final UpdatePatientNotesUseCase _updateNotes;
  final ListCabinetAppointmentsUseCase? _listAppointments;

  PatientsBloc({
    required ListCabinetPatientsUseCase listPatients,
    required GetCabinetPatientUseCase getPatient,
    required UpdatePatientNotesUseCase updateNotes,
    ListCabinetAppointmentsUseCase? listAppointments,
  })  : _list = listPatients,
        _getById = getPatient,
        _updateNotes = updateNotes,
        _listAppointments = listAppointments,
        super(const PatientsInitial()) {
    on<PatientsLoadRequested>(_onLoad);
    on<PatientsSearchChanged>(_onSearch);
    on<PatientsDetailLoadRequested>(_onDetailLoad);
    on<PatientsNotesUpdateRequested>(_onNotesUpdate);
    on<PatientExportPdfRequested>(_onExportPdf);
  }

  Future<void> _onLoad(
    PatientsLoadRequested event,
    Emitter<PatientsState> emit,
  ) async {
    emit(const PatientsLoading());
    try {
      final result = await _list();
      result.fold(
        (failure) => safeEmit(PatientsError(failure.message)),
        (patients) => safeEmit(PatientsLoaded(patients)),
      );
    } catch (_) {
      safeEmit(const PatientsError('Erreur de chargement.'));
    }
  }

  Future<void> _onSearch(
    PatientsSearchChanged event,
    Emitter<PatientsState> emit,
  ) async {
    emit(const PatientsLoading());
    try {
      final result = await _list(q: event.query);
      result.fold(
        (failure) => safeEmit(PatientsError(failure.message)),
        (patients) => safeEmit(PatientsLoaded(patients)),
      );
    } catch (_) {
      safeEmit(const PatientsError('Erreur de recherche.'));
    }
  }

  Future<void> _onDetailLoad(
    PatientsDetailLoadRequested event,
    Emitter<PatientsState> emit,
  ) async {
    emit(const PatientsLoading());
    try {
      final result = await _getById(event.id);
      // Historique RDV (#3372) : l'endpoint agenda cabinet n'accepte pas de
      // filtre patient — on filtre côté client. Best-effort : un échec laisse
      // l'historique vide sans casser la fiche.
      var appointments = const <CabinetAppointment>[];
      final listAppointments = _listAppointments;
      if (listAppointments != null) {
        try {
          final apptsResult = await listAppointments();
          appointments = apptsResult.fold(
            (_) => const [],
            (all) {
              final own = all.where((a) => a.patientId == event.id).toList()
                ..sort((a, b) => b.startsAt.compareTo(a.startsAt));
              return own;
            },
          );
        } catch (_) {
          appointments = const [];
        }
      }
      result.fold(
        (failure) => safeEmit(PatientDetailError(failure.message)),
        (patient) => safeEmit(
          PatientDetailLoaded(patient, appointments: appointments),
        ),
      );
    } catch (_) {
      safeEmit(const PatientDetailError('Erreur de chargement.'));
    }
  }

  Future<void> _onNotesUpdate(
    PatientsNotesUpdateRequested event,
    Emitter<PatientsState> emit,
  ) async {
    final current = state;
    if (current is! PatientDetailLoaded) return;
    emit(current.copyWith(notesUpdating: true, clearNotesError: true));
    try {
      final result = await _updateNotes(event.id, event.notes);
      result.fold(
        (failure) => safeEmit(current.copyWith(
          notesUpdating: false,
          notesError: failure.message,
        )),
        (updated) => safeEmit(PatientDetailLoaded(updated)),
      );
    } catch (_) {
      safeEmit(current.copyWith(
          notesUpdating: false, notesError: 'Erreur inattendue.'));
    }
  }

  Future<void> _onExportPdf(
    PatientExportPdfRequested event,
    Emitter<PatientsState> emit,
  ) async {
    final current = state;
    if (current is! PatientDetailLoaded) return;
    try {
      final bytes = await _buildPatientPdf(event.patient);
      emit(PatientPdfReady(
        bytes: Uint8List.fromList(bytes),
        filename: 'patient_${event.patient.id}.pdf',
      ));
      // Re-emit current state so the UI stays on the patient detail screen.
      emit(current);
    } catch (_) {
      emit(const PatientExportError('Impossible de générer le PDF.'));
      emit(current);
    }
  }

  static Future<List<int>> _buildPatientPdf(CabinetPatient p) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Fiche patient',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Text('Nom : ${p.fullName}'),
            if (p.birthDate != null)
              pw.Text('Date de naissance : ${_fmt(p.birthDate!)}'),
            if (p.email != null) pw.Text('Email : ${p.email!}'),
            if (p.phone != null) pw.Text('Téléphone : ${p.phone!}'),
            if (p.lastVisitAt != null)
              pw.Text('Dernière visite : ${_fmt(p.lastVisitAt!)}'),
          ],
        ),
      ),
    );
    return doc.save();
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
