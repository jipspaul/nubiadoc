import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

// --------------- Events ---------------

abstract class PatientFicheEvent extends Equatable {
  const PatientFicheEvent();

  @override
  List<Object?> get props => [];
}

class ToggleClinicalVisibility extends PatientFicheEvent {
  const ToggleClinicalVisibility();
}

// --------------- State ---------------

class PatientFicheState extends Equatable {
  final bool showClinical;

  const PatientFicheState({this.showClinical = true});

  PatientFicheState copyWith({bool? showClinical}) =>
      PatientFicheState(showClinical: showClinical ?? this.showClinical);

  @override
  List<Object?> get props => [showClinical];
}

// --------------- Bloc ---------------

class PatientFicheBloc extends Bloc<PatientFicheEvent, PatientFicheState> {
  PatientFicheBloc() : super(const PatientFicheState()) {
    on<ToggleClinicalVisibility>(_onToggle);
  }

  void _onToggle(
    ToggleClinicalVisibility event,
    Emitter<PatientFicheState> emit,
  ) {
    emit(state.copyWith(showClinical: !state.showClinical));
  }
}
