import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';

import 'home_care_models.dart';

sealed class HomeCareTrackingState extends Equatable {
  const HomeCareTrackingState();

  @override
  List<Object?> get props => [];
}

final class HomeCareTrackingLoading extends HomeCareTrackingState {
  const HomeCareTrackingLoading();
}

final class HomeCareTrackingLoaded extends HomeCareTrackingState {
  const HomeCareTrackingLoaded(this.visit, {this.cancelling = false});

  final VisitRequest visit;
  final bool cancelling;

  @override
  List<Object?> get props => [visit, cancelling];
}

final class HomeCareTrackingError extends HomeCareTrackingState {
  const HomeCareTrackingError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Suivi d'une demande de visite (détail + annulation) : `GET
/// /v1/account/visit-requests/:id` et `POST
/// /v1/account/visit-requests/:id/cancel`. Pas de flux temps réel (le
/// domaine nurse n'expose pas encore de canal WS côté patient — cf.
/// `NurseCubit`, même limite côté infirmière) : le suivi passe par le
/// pull-to-refresh, pattern documenté dans `front/AGENTS.md`.
class HomeCareTrackingCubit extends Cubit<HomeCareTrackingState>
    with SafeEmitMixin<HomeCareTrackingState> {
  HomeCareTrackingCubit(this._api) : super(const HomeCareTrackingLoading());

  final ApiClient _api;
  String? _id;

  Future<void> load(String id) async {
    _id = id;
    safeEmit(const HomeCareTrackingLoading());
    try {
      final res =
          await _api.dio.get<Map<String, dynamic>>('/account/visit-requests/$id');
      safeEmit(HomeCareTrackingLoaded(VisitRequest.fromJson(res.data!)));
    } on DioException catch (e) {
      safeEmit(HomeCareTrackingError(_msg(e)));
    }
  }

  Future<void> refresh() async {
    final id = _id;
    if (id != null) await load(id);
  }

  Future<void> cancel() async {
    final current = state;
    if (current is! HomeCareTrackingLoaded || current.cancelling) return;
    safeEmit(HomeCareTrackingLoaded(current.visit, cancelling: true));
    try {
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/account/visit-requests/${current.visit.id}/cancel',
      );
      safeEmit(HomeCareTrackingLoaded(VisitRequest.fromJson(res.data!)));
    } on DioException catch (e) {
      safeEmit(HomeCareTrackingError(_msg(e)));
    }
  }

  String _msg(DioException e) {
    final code = e.response?.statusCode;
    if (code == 404) return 'Demande introuvable.';
    if (code == 409) return 'Cette demande ne peut plus être annulée.';
    return 'Erreur réseau (${code ?? 'hors ligne'}).';
  }
}
