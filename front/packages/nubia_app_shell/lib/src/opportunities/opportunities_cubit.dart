import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'opportunities_state.dart';

/// Widget « opportunités du moment » (#7213, DP-F1.b) : charge les 5
/// catégories exposées par `GET /v1/cabinet/opportunities` (#7214), partagé
/// entre les apps praticien/secrétariat comme [ProNotificationsCubit].
class OpportunitiesCubit extends Cubit<OpportunitiesState> {
  OpportunitiesCubit({
    required GetCabinetOpportunitiesUseCase getOpportunities,
  })  : _getOpportunities = getOpportunities,
        super(const OpportunitiesLoading());

  final GetCabinetOpportunitiesUseCase _getOpportunities;

  Future<void> load() async {
    emit(const OpportunitiesLoading());
    final result = await _getOpportunities();
    result.fold(
      (failure) => emit(OpportunitiesError(message: failure.message)),
      (categories) => emit(OpportunitiesLoaded(categories: categories)),
    );
  }
}
