import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';

import 'home_care_models.dart';

sealed class HomeCareListState extends Equatable {
  const HomeCareListState();

  @override
  List<Object?> get props => [];
}

final class HomeCareListLoading extends HomeCareListState {
  const HomeCareListLoading();
}

final class HomeCareListLoaded extends HomeCareListState {
  const HomeCareListLoaded(this.requests);

  final List<VisitRequest> requests;

  @override
  List<Object?> get props => [requests];
}

final class HomeCareListError extends HomeCareListState {
  const HomeCareListError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Liste des demandes de visite du patient (`GET /v1/account/visit-requests`,
/// récentes d'abord — cf. `list_account_visit_requests`).
class HomeCareListCubit extends Cubit<HomeCareListState>
    with SafeEmitMixin<HomeCareListState> {
  HomeCareListCubit(this._api) : super(const HomeCareListLoading());

  final ApiClient _api;

  Future<void> load() async {
    safeEmit(const HomeCareListLoading());
    try {
      final res =
          await _api.dio.get<List<dynamic>>('/account/visit-requests');
      final requests = (res.data ?? [])
          .map((e) => VisitRequest.fromJson(e as Map<String, dynamic>))
          .toList();
      safeEmit(HomeCareListLoaded(requests));
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      safeEmit(HomeCareListError('Erreur réseau (${code ?? 'hors ligne'}).'));
    }
  }
}
