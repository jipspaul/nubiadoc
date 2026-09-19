import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class CabinetBriefState extends Equatable {
  const CabinetBriefState();

  @override
  List<Object?> get props => [];
}

class CabinetBriefInitial extends CabinetBriefState {
  const CabinetBriefInitial();
}

class CabinetBriefLoading extends CabinetBriefState {
  const CabinetBriefLoading();
}

class CabinetBriefLoaded extends CabinetBriefState {
  final CabinetBrief brief;
  final String view;
  final String? date;
  final bool isExportingPdf;
  final List<int>? pdfBytes;
  final String? pdfFilename;
  final String? pdfError;

  const CabinetBriefLoaded({
    required this.brief,
    required this.view,
    this.date,
    this.isExportingPdf = false,
    this.pdfBytes,
    this.pdfFilename,
    this.pdfError,
  });

  CabinetBriefLoaded copyWith({
    CabinetBrief? brief,
    bool? isExportingPdf,
    List<int>? pdfBytes,
    String? pdfFilename,
    String? pdfError,
    bool clearPdf = false,
  }) =>
      CabinetBriefLoaded(
        brief: brief ?? this.brief,
        view: view,
        date: date,
        isExportingPdf: isExportingPdf ?? this.isExportingPdf,
        pdfBytes: clearPdf ? null : (pdfBytes ?? this.pdfBytes),
        pdfFilename: clearPdf ? null : (pdfFilename ?? this.pdfFilename),
        pdfError: clearPdf ? null : (pdfError ?? this.pdfError),
      );

  @override
  List<Object?> get props => [
        brief,
        view,
        date,
        isExportingPdf,
        pdfBytes,
        pdfFilename,
        pdfError,
      ];
}

class CabinetBriefError extends CabinetBriefState {
  final String message;
  const CabinetBriefError(this.message);

  @override
  List<Object?> get props => [message];
}
