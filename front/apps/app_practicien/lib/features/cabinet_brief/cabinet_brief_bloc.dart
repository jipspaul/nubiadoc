import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'cabinet_brief_event.dart';
import 'cabinet_brief_state.dart';

/// Brief cabinet jour/semaine/prothèses (#7191) : lecture depuis l'agenda
/// praticien, export PDF pour impression/partage (#7192).
class CabinetBriefBloc extends Bloc<CabinetBriefEvent, CabinetBriefState>
    with SafeEmitMixin<CabinetBriefState> {
  final GetCabinetBriefUseCase _getBrief;
  final GetCabinetBriefPdfUseCase _getBriefPdf;

  CabinetBriefBloc({
    required GetCabinetBriefUseCase getBrief,
    required GetCabinetBriefPdfUseCase getBriefPdf,
  })  : _getBrief = getBrief,
        _getBriefPdf = getBriefPdf,
        super(const CabinetBriefInitial()) {
    on<CabinetBriefLoadRequested>(_onLoad);
    on<CabinetBriefPdfRequested>(_onPdfRequested);
    on<CabinetBriefPdfConsumed>(_onPdfConsumed);
  }

  Future<void> _onLoad(
    CabinetBriefLoadRequested event,
    Emitter<CabinetBriefState> emit,
  ) async {
    safeEmit(const CabinetBriefLoading());
    final result = await _getBrief(view: event.view, date: event.date);
    result.fold(
      (failure) => safeEmit(CabinetBriefError(failure.message)),
      (brief) => safeEmit(CabinetBriefLoaded(
        brief: brief,
        view: event.view,
        date: event.date,
      )),
    );
  }

  Future<void> _onPdfRequested(
    CabinetBriefPdfRequested event,
    Emitter<CabinetBriefState> emit,
  ) async {
    final current = state;
    if (current is! CabinetBriefLoaded) return;
    safeEmit(current.copyWith(isExportingPdf: true, clearPdf: true));
    final result = await _getBriefPdf(view: current.view, date: current.date);
    result.fold(
      (failure) => safeEmit(
        current.copyWith(isExportingPdf: false, pdfError: failure.message),
      ),
      (bytes) => safeEmit(
        current.copyWith(
          isExportingPdf: false,
          pdfBytes: bytes,
          pdfFilename: 'brief-${current.view}.pdf',
        ),
      ),
    );
  }

  void _onPdfConsumed(
    CabinetBriefPdfConsumed event,
    Emitter<CabinetBriefState> emit,
  ) {
    final current = state;
    if (current is CabinetBriefLoaded) {
      safeEmit(current.copyWith(clearPdf: true));
    }
  }
}
