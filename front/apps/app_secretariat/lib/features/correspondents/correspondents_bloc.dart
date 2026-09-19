import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'correspondents_event.dart';
import 'correspondents_state.dart';

class CorrespondentsBloc extends Bloc<CorrespondentsEvent, CorrespondentsState>
    with SafeEmitMixin<CorrespondentsState> {
  final ListCabinetCorrespondentsUseCase _list;
  final CreateCabinetCorrespondentUseCase _create;
  final UpdateCabinetCorrespondentUseCase _update;
  final DeleteCabinetCorrespondentUseCase _delete;

  CorrespondentsBloc({
    required ListCabinetCorrespondentsUseCase list,
    required CreateCabinetCorrespondentUseCase create,
    required UpdateCabinetCorrespondentUseCase update,
    required DeleteCabinetCorrespondentUseCase delete,
  })  : _list = list,
        _create = create,
        _update = update,
        _delete = delete,
        super(const CorrespondentsInitial()) {
    on<CorrespondentsLoadRequested>(_onLoad);
    on<CorrespondentsCreateRequested>(_onCreate);
    on<CorrespondentsUpdateRequested>(_onUpdate);
    on<CorrespondentsDeleteRequested>(_onDelete);
  }

  Future<void> _onLoad(
    CorrespondentsLoadRequested event,
    Emitter<CorrespondentsState> emit,
  ) async {
    emit(const CorrespondentsLoading());
    final result = await _list();
    result.fold(
      (failure) => safeEmit(CorrespondentsError(failure.message)),
      (correspondents) => safeEmit(
        correspondents.isEmpty
            ? const CorrespondentsEmpty()
            : CorrespondentsLoaded(correspondents),
      ),
    );
  }

  Future<void> _onCreate(
    CorrespondentsCreateRequested event,
    Emitter<CorrespondentsState> emit,
  ) async {
    final result = await _create(
      displayName: event.displayName,
      specialty: event.specialty,
      email: event.email,
      phone: event.phone,
      address: event.address,
      rpps: event.rpps,
      notes: event.notes,
    );
    result.fold(
      (failure) => safeEmit(CorrespondentsMutationError(failure.message)),
      (_) => _onMutationSucceeded(),
    );
  }

  Future<void> _onUpdate(
    CorrespondentsUpdateRequested event,
    Emitter<CorrespondentsState> emit,
  ) async {
    final result = await _update(
      event.id,
      displayName: event.displayName,
      specialty: event.specialty,
      email: event.email,
      phone: event.phone,
      address: event.address,
      rpps: event.rpps,
      notes: event.notes,
    );
    result.fold(
      (failure) => safeEmit(CorrespondentsMutationError(failure.message)),
      (_) => _onMutationSucceeded(),
    );
  }

  Future<void> _onDelete(
    CorrespondentsDeleteRequested event,
    Emitter<CorrespondentsState> emit,
  ) async {
    final result = await _delete(event.id);
    result.fold(
      (failure) => safeEmit(CorrespondentsMutationError(failure.message)),
      (_) => _onMutationSucceeded(),
    );
  }

  void _onMutationSucceeded() {
    safeEmit(const CorrespondentsMutationSuccess());
    add(const CorrespondentsLoadRequested());
  }
}
