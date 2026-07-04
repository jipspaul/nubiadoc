import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class MyPharmacyState extends Equatable {
  const MyPharmacyState();

  @override
  List<Object?> get props => [];
}

class MyPharmacyLoading extends MyPharmacyState {
  const MyPharmacyLoading();
}

/// [pharmacy] null = aucune pharmacie déclarée.
class MyPharmacyLoaded extends MyPharmacyState {
  const MyPharmacyLoaded(this.pharmacy);

  final Pharmacy? pharmacy;

  @override
  List<Object?> get props => [pharmacy];
}

class MyPharmacyError extends MyPharmacyState {
  const MyPharmacyError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Pharmacie déclarée du patient (GET/PUT /v1/account/pharmacy).
class MyPharmacyCubit extends Cubit<MyPharmacyState> {
  MyPharmacyCubit({
    required GetMyPharmacyUseCase getMyPharmacy,
    required SetMyPharmacyUseCase setMyPharmacy,
  })  : _get = getMyPharmacy,
        _set = setMyPharmacy,
        super(const MyPharmacyLoading());

  final GetMyPharmacyUseCase _get;
  final SetMyPharmacyUseCase _set;

  Future<void> load() async {
    emit(const MyPharmacyLoading());
    final result = await _get();
    result.fold(
      (failure) => emit(MyPharmacyError(failure.message)),
      (pharmacy) => emit(MyPharmacyLoaded(pharmacy)),
    );
  }

  Future<void> declare(String pharmacyId) async {
    emit(const MyPharmacyLoading());
    final result = await _set(pharmacyId);
    result.fold(
      (failure) => emit(MyPharmacyError(failure.message)),
      (pharmacy) => emit(MyPharmacyLoaded(pharmacy)),
    );
  }
}
