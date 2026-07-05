import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// --------------- Events ---------------

abstract class PatientFicheEvent extends Equatable {
  const PatientFicheEvent();

  @override
  List<Object?> get props => [];
}

class ToggleClinicalVisibility extends PatientFicheEvent {
  const ToggleClinicalVisibility();
}

class ExportPdfRequested extends PatientFicheEvent {
  final CabinetPatient patient;
  const ExportPdfRequested(this.patient);

  @override
  List<Object?> get props => [patient.id];
}

// --------------- State ---------------

class PatientFicheState extends Equatable {
  final bool showClinical;
  final bool isExportingPdf;
  final String? exportPdfError;

  /// PDF généré, prêt à partager (bytes en mémoire — pas de filesystem,
  /// dart:io/path_provider lèvent sur Flutter web, #3369).
  final Uint8List? pdfBytes;
  final String? pdfFilename;

  const PatientFicheState({
    this.showClinical = true,
    this.isExportingPdf = false,
    this.exportPdfError,
    this.pdfBytes,
    this.pdfFilename,
  });

  PatientFicheState copyWith({bool? showClinical}) => PatientFicheState(
        showClinical: showClinical ?? this.showClinical,
        isExportingPdf: isExportingPdf,
        exportPdfError: exportPdfError,
        pdfBytes: pdfBytes,
        pdfFilename: pdfFilename,
      );

  @override
  List<Object?> get props =>
      [showClinical, isExportingPdf, exportPdfError, pdfBytes, pdfFilename];
}

// --------------- Bloc ---------------

class PatientFicheBloc extends Bloc<PatientFicheEvent, PatientFicheState> {
  PatientFicheBloc() : super(const PatientFicheState()) {
    on<ToggleClinicalVisibility>(_onToggle);
    on<ExportPdfRequested>(_onExportPdf);
  }

  void _onToggle(
    ToggleClinicalVisibility event,
    Emitter<PatientFicheState> emit,
  ) {
    emit(state.copyWith(showClinical: !state.showClinical));
  }

  Future<void> _onExportPdf(
    ExportPdfRequested event,
    Emitter<PatientFicheState> emit,
  ) async {
    emit(PatientFicheState(
      showClinical: state.showClinical,
      isExportingPdf: true,
    ));
    try {
      final bytes = await _buildPatientPdf(event.patient);
      emit(PatientFicheState(
        showClinical: state.showClinical,
        pdfBytes: Uint8List.fromList(bytes),
        pdfFilename: 'patient_${event.patient.id}.pdf',
      ));
    } catch (_) {
      emit(PatientFicheState(
        showClinical: state.showClinical,
        exportPdfError: "Échec de l'export PDF",
      ));
    }
  }
}

// --------------- PDF builder ---------------

Future<List<int>> _buildPatientPdf(CabinetPatient patient) async {
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Padding(
        padding: const pw.EdgeInsets.all(32),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Fiche patient',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 24),
            pw.Text(
              patient.fullName,
              style: pw.TextStyle(fontSize: 18),
            ),
            if (patient.birthDate != null) ...[
              pw.SizedBox(height: 8),
              pw.Text('Date de naissance : ${_formatDate(patient.birthDate!)}'),
            ],
            if (patient.email != null) ...[
              pw.SizedBox(height: 8),
              pw.Text('Email : ${patient.email}'),
            ],
            if (patient.phone != null) ...[
              pw.SizedBox(height: 8),
              pw.Text('Téléphone : ${patient.phone}'),
            ],
            if (patient.lastVisitAt != null) ...[
              pw.SizedBox(height: 8),
              pw.Text('Dernière visite : ${_formatDate(patient.lastVisitAt!)}'),
            ],
          ],
        ),
      ),
    ),
  );
  return doc.save();
}

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
