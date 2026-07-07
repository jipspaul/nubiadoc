import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class ReferringDoctorState extends Equatable {
  const ReferringDoctorState();

  @override
  List<Object?> get props => [];
}

class ReferringDoctorLoading extends ReferringDoctorState {
  const ReferringDoctorLoading();
}

/// [doctor] null = aucun médecin traitant déclaré.
class ReferringDoctorLoaded extends ReferringDoctorState {
  const ReferringDoctorLoaded(this.doctor);

  final ReferringDoctor? doctor;

  @override
  List<Object?> get props => [doctor];
}

class ReferringDoctorError extends ReferringDoctorState {
  const ReferringDoctorError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Médecin traitant déclaré du patient (GET/PUT /v1/account/referring-doctor).
class ReferringDoctorCubit extends Cubit<ReferringDoctorState> {
  ReferringDoctorCubit({
    required GetReferringDoctorUseCase getReferringDoctor,
    required SetReferringDoctorUseCase setReferringDoctor,
  })  : _get = getReferringDoctor,
        _set = setReferringDoctor,
        super(const ReferringDoctorLoading());

  final GetReferringDoctorUseCase _get;
  final SetReferringDoctorUseCase _set;

  Future<void> load() async {
    emit(const ReferringDoctorLoading());
    final result = await _get();
    result.fold(
      (failure) => emit(ReferringDoctorError(failure.message)),
      (doctor) => emit(ReferringDoctorLoaded(doctor)),
    );
  }

  /// Déclare un praticien existant de l'annuaire Nubia.
  Future<void> declareProvider(ProviderResult provider) => _declare(
        providerId: provider.id,
        name: provider.displayName,
        specialty: provider.specialty,
        address: provider.address,
      );

  /// Déclare un médecin saisi librement (absent de la base Nubia).
  Future<void> declareManual({
    required String name,
    String? specialty,
    String? phone,
    String? email,
    String? address,
  }) =>
      _declare(
        name: name,
        specialty: specialty,
        phone: phone,
        email: email,
        address: address,
      );

  Future<void> _declare({
    String? providerId,
    required String name,
    String? specialty,
    String? phone,
    String? email,
    String? address,
  }) async {
    emit(const ReferringDoctorLoading());
    final result = await _set(
      providerId: providerId,
      name: name,
      specialty: specialty,
      phone: phone,
      email: email,
      address: address,
    );
    result.fold(
      (failure) => emit(ReferringDoctorError(failure.message)),
      (doctor) => emit(ReferringDoctorLoaded(doctor)),
    );
  }
}
