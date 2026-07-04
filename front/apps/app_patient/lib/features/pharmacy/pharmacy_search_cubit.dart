import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class PharmacySearchState extends Equatable {
  const PharmacySearchState();

  @override
  List<Object?> get props => [];
}

class PharmacySearchIdle extends PharmacySearchState {
  const PharmacySearchIdle();
}

class PharmacySearchLoading extends PharmacySearchState {
  const PharmacySearchLoading();
}

class PharmacySearchResults extends PharmacySearchState {
  const PharmacySearchResults(this.pharmacies);

  final List<Pharmacy> pharmacies;

  @override
  List<Object?> get props => [pharmacies];
}

class PharmacySearchError extends PharmacySearchState {
  const PharmacySearchError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Recherche dans l'annuaire public (GET /v1/pharmacies).
/// La géolocalisation est optionnelle : sans position, recherche par nom.
class PharmacySearchCubit extends Cubit<PharmacySearchState> {
  PharmacySearchCubit({required SearchPharmaciesUseCase search})
      : _search = search,
        super(const PharmacySearchIdle());

  final SearchPharmaciesUseCase _search;

  Future<void> search(String query, {double? lat, double? lng}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty && lat == null) {
      emit(const PharmacySearchIdle());
      return;
    }
    emit(const PharmacySearchLoading());
    final result = await _search(
      query: trimmed.isEmpty ? null : trimmed,
      lat: lat,
      lng: lng,
    );
    result.fold(
      (failure) => emit(PharmacySearchError(failure.message)),
      (pharmacies) => emit(PharmacySearchResults(pharmacies)),
    );
  }
}
