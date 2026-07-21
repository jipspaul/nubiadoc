import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'appointment_motifs_event.dart';
import 'appointment_motifs_state.dart';

class AppointmentMotifsBloc
    extends Bloc<AppointmentMotifsEvent, AppointmentMotifsState>
    with SafeEmitMixin<AppointmentMotifsState> {
  final ListAppointmentMotifsUseCase _list;
  final CreateAppointmentMotifUseCase _create;
  final UpdateAppointmentMotifUseCase _update;
  final DeleteAppointmentMotifUseCase _delete;

  AppointmentMotifsBloc({
    required ListAppointmentMotifsUseCase list,
    required CreateAppointmentMotifUseCase create,
    required UpdateAppointmentMotifUseCase update,
    required DeleteAppointmentMotifUseCase delete,
  })  : _list = list,
        _create = create,
        _update = update,
        _delete = delete,
        super(const AppointmentMotifsInitial()) {
    on<AppointmentMotifsLoadRequested>(_onLoad);
    on<AppointmentMotifsCreateRequested>(_onCreate);
    on<AppointmentMotifsUpdateRequested>(_onUpdate);
    on<AppointmentMotifsDeleteRequested>(_onDelete);
  }

  Future<void> _onLoad(
    AppointmentMotifsLoadRequested event,
    Emitter<AppointmentMotifsState> emit,
  ) async {
    emit(const AppointmentMotifsLoading());
    final result = await _list();
    result.fold(
      (failure) => safeEmit(AppointmentMotifsError(failure.message)),
      (motifs) => safeEmit(
        motifs.isEmpty
            ? const AppointmentMotifsEmpty()
            : AppointmentMotifsLoaded(motifs),
      ),
    );
  }

  Future<void> _onCreate(
    AppointmentMotifsCreateRequested event,
    Emitter<AppointmentMotifsState> emit,
  ) async {
    final result = await _create(
      label: event.label,
      defaultDurationMinutes: event.defaultDurationMinutes,
    );
    result.fold(
      (failure) => _emitFailure(failure),
      (_) => _onMutationSucceeded(),
    );
  }

  Future<void> _onUpdate(
    AppointmentMotifsUpdateRequested event,
    Emitter<AppointmentMotifsState> emit,
  ) async {
    final result = await _update(
      event.id,
      label: event.label,
      defaultDurationMinutes: event.defaultDurationMinutes,
    );
    result.fold(
      (failure) => _emitFailure(failure),
      (_) => _onMutationSucceeded(),
    );
  }

  Future<void> _onDelete(
    AppointmentMotifsDeleteRequested event,
    Emitter<AppointmentMotifsState> emit,
  ) async {
    final result = await _delete(event.id);
    result.fold(
      (failure) => _emitFailure(failure),
      (_) => _onMutationSucceeded(),
    );
  }

  /// 403 (admin-only, cf. #4085) distingué de l'erreur générique — la
  /// liste (GET) n'est elle-même jamais 403 pour un rôle pro.
  void _emitFailure(Failure failure) {
    if (failure is ServerFailure && failure.statusCode == 403) {
      safeEmit(AppointmentMotifsWriteForbidden(failure.message));
    } else {
      safeEmit(AppointmentMotifsError(failure.message));
    }
  }

  void _onMutationSucceeded() {
    safeEmit(const AppointmentMotifsMutationSuccess());
    add(const AppointmentMotifsLoadRequested());
  }
}
