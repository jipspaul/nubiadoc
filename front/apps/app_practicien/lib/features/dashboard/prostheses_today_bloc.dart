import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

sealed class ProsthesesTodayEvent extends Equatable {
  const ProsthesesTodayEvent();

  @override
  List<Object?> get props => [];
}

final class ProsthesesTodayLoadRequested extends ProsthesesTodayEvent {
  const ProsthesesTodayLoadRequested();
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

sealed class ProsthesesTodayState extends Equatable {
  const ProsthesesTodayState();

  @override
  List<Object?> get props => [];
}

final class ProsthesesTodayInitial extends ProsthesesTodayState {
  const ProsthesesTodayInitial();
}

final class ProsthesesTodayLoading extends ProsthesesTodayState {
  const ProsthesesTodayLoading();
}

final class ProsthesesTodayLoaded extends ProsthesesTodayState {
  final List<TodayLabWorkOrder> orders;

  const ProsthesesTodayLoaded(this.orders);

  @override
  List<Object?> get props => [orders];
}

final class ProsthesesTodayError extends ProsthesesTodayState {
  final String message;

  const ProsthesesTodayError(this.message);

  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// BLoC
// ---------------------------------------------------------------------------

/// Widget dashboard « Prothèses du jour » (#7207) : liste en lecture seule
/// des bons dont le RDV de pose tombe aujourd'hui ou demain
/// (`GET /v1/cabinet/lab-work-orders/today`, #7208). Le changement de statut
/// se fait depuis l'écran de suivi labo (`LabWorkOrdersBloc`), pas ici.
class ProsthesesTodayBloc
    extends Bloc<ProsthesesTodayEvent, ProsthesesTodayState> {
  final ListTodayLabWorkOrdersUseCase _listToday;

  ProsthesesTodayBloc({required ListTodayLabWorkOrdersUseCase listToday})
      : _listToday = listToday,
        super(const ProsthesesTodayInitial()) {
    on<ProsthesesTodayLoadRequested>(_onLoad);
  }

  Future<void> _onLoad(
    ProsthesesTodayLoadRequested event,
    Emitter<ProsthesesTodayState> emit,
  ) async {
    emit(const ProsthesesTodayLoading());
    final result = await _listToday();
    result.fold(
      (failure) => emit(ProsthesesTodayError(failure.message)),
      (orders) => emit(ProsthesesTodayLoaded(orders)),
    );
  }
}
