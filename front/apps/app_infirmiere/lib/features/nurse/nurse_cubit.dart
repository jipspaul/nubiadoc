import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nubia_core/nubia_core.dart';

/// Une offre de visite reçue par l'infirmière (`GET /v1/nurse/offers`).
class NurseOffer extends Equatable {
  const NurseOffer({
    required this.id,
    required this.requestedActs,
    required this.patientDisplayName,
    required this.address,
    required this.status,
  });

  final String id;
  final List<String> requestedActs;
  final String patientDisplayName;
  final Map<String, dynamic> address;
  final String status;

  static NurseOffer fromJson(Map<String, dynamic> j) => NurseOffer(
        id: j['id'] as String,
        requestedActs:
            (j['requested_acts'] as List<dynamic>? ?? []).cast<String>(),
        patientDisplayName: j['patient_display_name'] as String? ?? '',
        address: (j['address'] as Map<String, dynamic>?) ?? const {},
        status: j['status'] as String? ?? 'offered',
      );

  @override
  List<Object?> get props => [id, status];
}

/// État de l'app infirmière (disponibilité + offres + visite en cours).
class NurseState extends Equatable {
  const NurseState({
    this.online = false,
    this.loading = false,
    this.offers = const [],
    this.activeVisit,
    this.error,
  });

  final bool online;
  final bool loading;
  final List<NurseOffer> offers;
  final NurseOffer? activeVisit;
  final String? error;

  NurseState copyWith({
    bool? online,
    bool? loading,
    List<NurseOffer>? offers,
    NurseOffer? activeVisit,
    bool clearActiveVisit = false,
    String? error,
    bool clearError = false,
  }) =>
      NurseState(
        online: online ?? this.online,
        loading: loading ?? this.loading,
        offers: offers ?? this.offers,
        activeVisit:
            clearActiveVisit ? null : (activeVisit ?? this.activeVisit),
        error: clearError ? null : (error ?? this.error),
      );

  @override
  List<Object?> get props => [online, loading, offers, activeVisit, error];
}

/// Pilote le domaine infirmier via l'ApiClient partagé (Dio + token Bearer
/// injecté par l'auth interceptor). Appelle les endpoints `/v1/nurse/*` du
/// backend (slice 1/2). Voir le TODO auth dans [InfirmiereAuthCubit] : les
/// endpoints exigent un token `kind:nurse` (select-nurse-context, à câbler).
class NurseCubit extends Cubit<NurseState> {
  NurseCubit(this._api) : super(const NurseState());

  final ApiClient _api;
  Dio get _dio => _api.dio;

  /// Charge l'état réel de disponibilité depuis le serveur (`GET
  /// /nurse/profile`). À appeler au montage de l'écran : `online` vaut
  /// `false` par défaut dans [NurseState] tant que ce chargement n'a pas
  /// abouti, ce qui ne reflète pas forcément `nurse.is_online` en base
  /// (mise à jour lors d'une session précédente, autre appareil, etc.).
  Future<void> loadProfile() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/nurse/profile');
      final isOnline = res.data?['is_online'] as bool? ?? false;
      emit(state.copyWith(online: isOnline, clearError: true));
    } on DioException catch (e) {
      emit(state.copyWith(error: _msg(e)));
    }
  }

  Future<void> loadOffers() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final res = await _dio.get<List<dynamic>>('/nurse/offers');
      final offers = (res.data ?? [])
          .map((e) => NurseOffer.fromJson(e as Map<String, dynamic>))
          .toList();
      emit(state.copyWith(loading: false, offers: offers));
    } on DioException catch (e) {
      emit(state.copyWith(loading: false, error: _msg(e)));
    }
  }

  /// Recharge la visite en cours (`GET /nurse/visits`) — à appeler au montage
  /// de l'écran comme [loadProfile]/[loadOffers] : `activeVisit` n'est
  /// sinon alimenté que par la réponse de [accept]/[transition], perdue dès
  /// que le cubit est recréé (redémarrage, retour au premier plan) (#6244).
  Future<void> loadActiveVisit() async {
    try {
      final res = await _dio.get<dynamic>('/nurse/visits');
      final data = res.data;
      if (data is Map<String, dynamic> && data.isNotEmpty) {
        emit(state.copyWith(
            activeVisit: NurseOffer.fromJson(data), clearError: true));
      } else {
        emit(state.copyWith(clearActiveVisit: true, clearError: true));
      }
    } on DioException catch (e) {
      emit(state.copyWith(error: _msg(e)));
    }
  }

  Future<void> setOnline(bool online) async {
    // En passant en ligne, on pousse la position réelle (matching de proximité).
    double? lat, lng;
    if (online) {
      final pos = await _currentPosition();
      lat = pos?.latitude;
      lng = pos?.longitude;
    }
    try {
      await _dio.patch<Map<String, dynamic>>(
        '/nurse/availability',
        data: {
          'is_online': online,
          if (lat != null && lng != null) 'lat': lat,
          if (lat != null && lng != null) 'lng': lng,
        },
      );
      emit(state.copyWith(online: online, clearError: true));
      if (online) await loadOffers();
    } on DioException catch (e) {
      emit(state.copyWith(error: _msg(e)));
    }
  }

  /// Position courante (permission à la volée). Null si refusée/indispo — la
  /// dispo est alors envoyée sans coordonnées (le back garde l'ancienne position).
  Future<Position?> _currentPosition() async {
    try {
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
    } catch (_) {
      return null;
    }
  }

  Future<void> accept(NurseOffer offer) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final res = await _dio
          .post<Map<String, dynamic>>('/nurse/visits/${offer.id}/accept');
      final visit = NurseOffer.fromJson(res.data ?? const {});
      final remaining =
          state.offers.where((o) => o.id != offer.id).toList();
      emit(state.copyWith(
          loading: false, activeVisit: visit, offers: remaining));
    } on DioException catch (e) {
      emit(state.copyWith(loading: false, error: _msg(e)));
    }
  }

  Future<void> decline(NurseOffer offer) async {
    try {
      await _dio.post<Map<String, dynamic>>('/nurse/offers/${offer.id}/decline');
      emit(state.copyWith(
          offers: state.offers.where((o) => o.id != offer.id).toList()));
    } on DioException catch (e) {
      emit(state.copyWith(error: _msg(e)));
    }
  }

  /// Avance la visite en cours : `en-route` → `arrived` → `done`.
  Future<void> transition(String action) async {
    final visit = state.activeVisit;
    if (visit == null) return;
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final res = await _dio
          .post<Map<String, dynamic>>('/nurse/visits/${visit.id}/$action');
      final updated = NurseOffer.fromJson(res.data ?? const {});
      if (updated.status == 'done') {
        emit(state.copyWith(loading: false, clearActiveVisit: true));
      } else {
        emit(state.copyWith(loading: false, activeVisit: updated));
      }
    } on DioException catch (e) {
      emit(state.copyWith(loading: false, error: _msg(e)));
    }
  }

  String _msg(DioException e) {
    final code = e.response?.statusCode;
    if (code == 403) return 'Accès infirmier requis (contexte non sélectionné).';
    if (code == 409) return 'Action impossible dans cet état.';
    return 'Erreur réseau (${code ?? 'hors ligne'}).';
  }
}
