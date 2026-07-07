import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class ReferringDoctorSearchState extends Equatable {
  const ReferringDoctorSearchState();

  @override
  List<Object?> get props => [];
}

class ReferringDoctorSearchLoading extends ReferringDoctorSearchState {
  const ReferringDoctorSearchLoading();
}

class ReferringDoctorSearchResults extends ReferringDoctorSearchState {
  const ReferringDoctorSearchResults(this.providers);

  final List<ProviderResult> providers;

  @override
  List<Object?> get props => [providers];
}

class ReferringDoctorSearchError extends ReferringDoctorSearchState {
  const ReferringDoctorSearchError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Recherche parmi les praticiens Nubia existants (GET /v1/search/providers).
class ReferringDoctorSearchCubit extends Cubit<ReferringDoctorSearchState> {
  ReferringDoctorSearchCubit({required SearchProvidersUseCase search})
      : _search = search,
        super(const ReferringDoctorSearchLoading());

  final SearchProvidersUseCase _search;

  Future<void> search(String query) async {
    emit(const ReferringDoctorSearchLoading());
    final result = await _search(query: query.trim());
    result.fold(
      (failure) => emit(ReferringDoctorSearchError(failure.message)),
      (providers) => emit(ReferringDoctorSearchResults(providers)),
    );
  }
}
