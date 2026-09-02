import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nubia_core/nubia_core.dart';

import 'home_care_models.dart';

sealed class HomeCareRequestState extends Equatable {
  const HomeCareRequestState();

  @override
  List<Object?> get props => [];
}

final class HomeCareRequestIdle extends HomeCareRequestState {
  const HomeCareRequestIdle();
}

final class HomeCareRequestEstimating extends HomeCareRequestState {
  const HomeCareRequestEstimating();
}

final class HomeCareRequestEstimated extends HomeCareRequestState {
  const HomeCareRequestEstimated(this.priceCents);

  final int priceCents;

  @override
  List<Object?> get props => [priceCents];
}

final class HomeCareRequestSubmitting extends HomeCareRequestState {
  const HomeCareRequestSubmitting();
}

final class HomeCareRequestCreated extends HomeCareRequestState {
  const HomeCareRequestCreated(this.visit);

  final VisitRequest visit;

  @override
  List<Object?> get props => [visit];
}

final class HomeCareRequestFailure extends HomeCareRequestState {
  const HomeCareRequestFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Pilote la création d'une demande de visite infirmière : devis indicatif
/// (`POST /v1/account/visit-requests/estimate`) puis demande géolocalisée
/// (`POST /v1/account/visit-requests`, fan-out aux infirmières proches en
/// ligne côté back). Miroir côté patient de `NurseCubit`
/// (`app_infirmiere/lib/features/nurse/nurse_cubit.dart`) : appelle
/// l'`ApiClient` partagé directement, sans repository dédié — même
/// justification que côté infirmière, domaine encore MVP (slice 1/2).
class HomeCareRequestCubit extends Cubit<HomeCareRequestState>
    with SafeEmitMixin<HomeCareRequestState> {
  HomeCareRequestCubit(
    this._api, {
    Future<Position?> Function()? currentPosition,
  })  : _currentPosition = currentPosition ?? _defaultCurrentPosition,
        super(const HomeCareRequestIdle());

  final ApiClient _api;
  final Future<Position?> Function() _currentPosition;
  Dio get _dio => _api.dio;

  /// Invalide un devis affiché quand la sélection d'actes change — évite
  /// d'afficher un prix qui ne correspond plus aux actes cochés.
  void resetEstimate() {
    if (state is HomeCareRequestEstimated) {
      safeEmit(const HomeCareRequestIdle());
    }
  }

  Future<void> estimate(List<String> acts) async {
    if (acts.isEmpty) {
      safeEmit(const HomeCareRequestIdle());
      return;
    }
    safeEmit(const HomeCareRequestEstimating());
    final position = await _currentPosition();
    if (position == null) {
      safeEmit(const HomeCareRequestFailure(
          'Position indisponible : activez la géolocalisation.'));
      return;
    }
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/account/visit-requests/estimate',
        data: {
          'lat': position.latitude,
          'lng': position.longitude,
          'requested_acts': acts,
        },
      );
      safeEmit(HomeCareRequestEstimated(
          res.data!['estimated_price_cents'] as int));
    } on DioException catch (e) {
      safeEmit(HomeCareRequestFailure(_msg(e)));
    }
  }

  Future<void> submit({
    required List<String> acts,
    required String line1,
    required String city,
    required String postalCode,
    required String patientDisplayName,
    String? notes,
  }) async {
    safeEmit(const HomeCareRequestSubmitting());
    final position = await _currentPosition();
    if (position == null) {
      safeEmit(const HomeCareRequestFailure(
          'Position indisponible : activez la géolocalisation.'));
      return;
    }
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/account/visit-requests',
        data: {
          'lat': position.latitude,
          'lng': position.longitude,
          'address': {
            'line1': line1,
            'city': city,
            'postal_code': postalCode,
          },
          'requested_acts': acts,
          'patient_display_name': patientDisplayName,
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        },
      );
      safeEmit(HomeCareRequestCreated(VisitRequest.fromJson(res.data!)));
    } on DioException catch (e) {
      safeEmit(HomeCareRequestFailure(_msg(e)));
    }
  }

  /// Position courante (permission à la volée) — même stratégie que
  /// `NurseCubit._currentPosition` côté infirmière.
  ///
  /// `.timeout` couvre le cas où le navigateur ne rappelle jamais le callback
  /// (permission refusée sans dialogue, capteur indisponible) : sans borne,
  /// `estimate`/`submit` restaient bloqués en `Estimating`/`Submitting` pour
  /// toujours, sans jamais atteindre la branche `position == null`.
  static Future<Position?> _defaultCurrentPosition() async {
    try {
      return await _requestCurrentPosition()
          .timeout(const Duration(seconds: 10), onTimeout: () => null);
    } catch (_) {
      return null;
    }
  }

  static Future<Position?> _requestCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }
    return await Geolocator.getCurrentPosition();
  }

  String _msg(DioException e) {
    final code = e.response?.statusCode;
    if (code == 422) return 'Actes ou coordonnées invalides.';
    if (code == 409) return 'Une demande de visite est déjà en cours.';
    return 'Erreur réseau (${code ?? 'hors ligne'}).';
  }
}
