import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'compliance_event.dart';
import 'compliance_state.dart';

/// Échéancier de conformité ARS/DMSM du cabinet (#7169/#7170) : liste
/// (à venir/échu/fait, alertes calculées côté back), création d'items,
/// clôture, rattachement de pièce justificative.
class ComplianceBloc extends Bloc<ComplianceEvent, ComplianceState>
    with SafeEmitMixin<ComplianceState> {
  ComplianceBloc({
    required ListComplianceItemsUseCase listItems,
    required CreateComplianceItemUseCase createItem,
    required CompleteComplianceItemUseCase completeItem,
    required AttachComplianceEvidenceUseCase attachEvidence,
  })  : _listItems = listItems,
        _createItem = createItem,
        _completeItem = completeItem,
        _attachEvidence = attachEvidence,
        super(const ComplianceInitial()) {
    on<ComplianceLoadRequested>(_onLoad);
    on<ComplianceCreateRequested>(_onCreate);
    on<ComplianceCompleteRequested>(_onComplete);
    on<ComplianceEvidenceAttachRequested>(_onAttachEvidence);
  }

  final ListComplianceItemsUseCase _listItems;
  final CreateComplianceItemUseCase _createItem;
  final CompleteComplianceItemUseCase _completeItem;
  final AttachComplianceEvidenceUseCase _attachEvidence;

  Future<void> _onLoad(
    ComplianceLoadRequested event,
    Emitter<ComplianceState> emit,
  ) async {
    emit(const ComplianceLoading());
    final result = await _listItems();
    result.fold(
      (failure) => safeEmit(ComplianceError(failure.message)),
      (items) => safeEmit(ComplianceLoaded(items: items)),
    );
  }

  Future<void> _onCreate(
    ComplianceCreateRequested event,
    Emitter<ComplianceState> emit,
  ) async {
    final current = state;
    if (current is! ComplianceLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _createItem(
      kind: event.kind,
      label: event.label,
      subjectUserId: event.subjectUserId,
      equipmentLabel: event.equipmentLabel,
      dueDate: event.dueDate,
      recurrenceMonths: event.recurrenceMonths,
    );
    await result.fold(
      (failure) async => safeEmit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) => _onLoad(const ComplianceLoadRequested(), emit),
    );
  }

  Future<void> _onComplete(
    ComplianceCompleteRequested event,
    Emitter<ComplianceState> emit,
  ) async {
    final current = state;
    if (current is! ComplianceLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _completeItem(event.itemId);
    await result.fold(
      (failure) async => safeEmit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) => _onLoad(const ComplianceLoadRequested(), emit),
    );
  }

  Future<void> _onAttachEvidence(
    ComplianceEvidenceAttachRequested event,
    Emitter<ComplianceState> emit,
  ) async {
    final current = state;
    if (current is! ComplianceLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _attachEvidence(
      itemId: event.itemId,
      evidenceDocumentId: event.evidenceDocumentId,
    );
    await result.fold(
      (failure) async => safeEmit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) => _onLoad(const ComplianceLoadRequested(), emit),
    );
  }
}
