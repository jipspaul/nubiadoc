import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/appointment_repository.dart';
import '../models/appointment.dart';
import 'appointment_event.dart';
import 'appointment_state.dart';

class AppointmentBloc extends Bloc<AppointmentEvent, AppointmentState> {
  AppointmentBloc({required AppointmentRepository repository})
      : _repository = repository,
        super(const AppointmentInitial()) {
    on<AppointmentLoadRequested>(_onLoadRequested);
    on<AppointmentDetailRequested>(_onDetailRequested);
    on<AppointmentBookRequested>(_onBookRequested);
    on<AppointmentCancelRequested>(_onCancelRequested);
  }

  final AppointmentRepository _repository;

  Future<void> _onLoadRequested(
    AppointmentLoadRequested event,
    Emitter<AppointmentState> emit,
  ) async {
    emit(const AppointmentLoading());
    try {
      final all = await _repository.fetchAll();
      final filtered = _filterByTab(all, event.tab);
      emit(AppointmentListLoaded(filtered, tab: event.tab));
    } catch (e) {
      emit(AppointmentError(e.toString()));
    }
  }

  Future<void> _onDetailRequested(
    AppointmentDetailRequested event,
    Emitter<AppointmentState> emit,
  ) async {
    emit(const AppointmentLoading());
    try {
      final apt = await _repository.fetchById(event.id);
      emit(AppointmentDetailLoaded(apt));
    } catch (e) {
      emit(AppointmentError(e.toString()));
    }
  }

  Future<void> _onBookRequested(
    AppointmentBookRequested event,
    Emitter<AppointmentState> emit,
  ) async {
    emit(const AppointmentLoading());
    try {
      final apt = await _repository.book(
        providerId: event.providerId,
        startsAt: event.startsAt,
        motif: event.motif,
      );
      emit(AppointmentBooked(apt));
    } catch (e) {
      emit(AppointmentError(e.toString()));
    }
  }

  Future<void> _onCancelRequested(
    AppointmentCancelRequested event,
    Emitter<AppointmentState> emit,
  ) async {
    final current = state;
    final currentList = current is AppointmentListLoaded
        ? current.appointments
        : current is AppointmentCancelling
            ? current.appointments
            : <Appointment>[];

    emit(AppointmentCancelling(currentList));
    try {
      await _repository.cancel(event.id);
      final all = await _repository.fetchAll();
      final filtered = _filterByTab(all, AppointmentTab.upcoming);
      emit(AppointmentListLoaded(filtered));
    } catch (e) {
      emit(AppointmentError(e.toString()));
    }
  }

  List<Appointment> _filterByTab(
    List<Appointment> all,
    AppointmentTab tab,
  ) {
    return switch (tab) {
      AppointmentTab.upcoming => all
          .where((a) =>
              a.status == AppointmentStatus.requested ||
              a.status == AppointmentStatus.confirmed)
          .toList(),
      AppointmentTab.history => all
          .where((a) =>
              a.status == AppointmentStatus.done ||
              a.status == AppointmentStatus.cancelled)
          .toList(),
    };
  }
}

