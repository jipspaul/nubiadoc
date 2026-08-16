import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

// ── Events ────────────────────────────────────────────────────────────────────

sealed class PatientOrdersEvent extends Equatable {
  const PatientOrdersEvent();

  @override
  List<Object?> get props => [];
}

class PatientOrdersRequested extends PatientOrdersEvent {
  const PatientOrdersRequested();
}

// ── States ────────────────────────────────────────────────────────────────────

sealed class PatientOrdersState extends Equatable {
  const PatientOrdersState();

  @override
  List<Object?> get props => [];
}

class PatientOrdersLoading extends PatientOrdersState {
  const PatientOrdersLoading();
}

class PatientOrdersLoaded extends PatientOrdersState {
  const PatientOrdersLoaded(this.orders);

  final List<PharmacyOrder> orders;

  @override
  List<Object?> get props => [orders];
}

class PatientOrdersError extends PatientOrdersState {
  const PatientOrdersError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Liste des commandes du patient.
class PatientOrdersBloc extends Bloc<PatientOrdersEvent, PatientOrdersState> {
  PatientOrdersBloc({required ListPatientPharmacyOrdersUseCase list})
      : _list = list,
        super(const PatientOrdersLoading()) {
    on<PatientOrdersRequested>(_onRequested);
  }

  final ListPatientPharmacyOrdersUseCase _list;

  Future<void> _onRequested(
    PatientOrdersRequested event,
    Emitter<PatientOrdersState> emit,
  ) async {
    emit(const PatientOrdersLoading());
    final result = await _list();
    result.fold(
      (failure) => emit(PatientOrdersError(failure.message)),
      (orders) => emit(PatientOrdersLoaded(orders)),
    );
  }
}

// ── Détail + temps réel + QR ─────────────────────────────────────────────────

sealed class PatientOrderDetailState extends Equatable {
  const PatientOrderDetailState();

  @override
  List<Object?> get props => [];
}

class PatientOrderDetailLoading extends PatientOrderDetailState {
  const PatientOrderDetailLoading();
}

class PatientOrderDetailLoaded extends PatientOrderDetailState {
  const PatientOrderDetailLoaded(
    this.order, {
    this.pickupToken,
    this.cancelling = false,
    this.pharmacyPhone,
    this.pharmacy,
  });

  final PharmacyOrder order;

  /// Token opaque du QR (récupéré uniquement quand la commande est prête).
  final String? pickupToken;
  final bool cancelling;

  /// Téléphone de la pharmacie déclarée (récupéré uniquement quand la
  /// commande est refusée, pour le bouton « Appeler la pharmacie », #5351).
  final String? pharmacyPhone;

  /// Pharmacie déclarée du patient — adresse/distance/téléphone pour la
  /// carte pharmacie de l'écran de suivi (design-v2, #5350).
  final Pharmacy? pharmacy;

  @override
  List<Object?> get props =>
      [order, pickupToken, cancelling, pharmacyPhone, pharmacy];
}

class PatientOrderDetailError extends PatientOrderDetailState {
  const PatientOrderDetailError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Détail d'une commande patient : suivi temps réel (port events) + QR de
/// retrait (token chargé automatiquement quand la commande est prête) +
/// annulation (tant que la commande n'est pas prête).
class PatientOrderDetailCubit extends Cubit<PatientOrderDetailState> {
  PatientOrderDetailCubit({
    required GetPatientPharmacyOrderUseCase get,
    required WatchPatientPharmacyOrderUseCase watch,
    required GetPickupTokenUseCase pickupToken,
    required CancelPharmacyOrderUseCase cancel,
    required GetMyPharmacyUseCase getMyPharmacy,
  })  : _get = get,
        _watch = watch,
        _pickupToken = pickupToken,
        _cancel = cancel,
        _getMyPharmacy = getMyPharmacy,
        super(const PatientOrderDetailLoading());

  final GetPatientPharmacyOrderUseCase _get;
  final WatchPatientPharmacyOrderUseCase _watch;
  final GetPickupTokenUseCase _pickupToken;
  final CancelPharmacyOrderUseCase _cancel;
  final GetMyPharmacyUseCase _getMyPharmacy;
  StreamSubscription<PharmacyOrder>? _subscription;
  String? _orderId;

  /// Pharmacie déclarée du patient — chargée une fois par [load] et réutilisée
  /// pour chaque émission suivante (carte pharmacie #5350, téléphone #5351).
  Pharmacy? _pharmacy;

  /// Relance le chargement de la dernière commande consultée (bouton Réessayer).
  Future<void> reload() async {
    final orderId = _orderId;
    if (orderId == null) return;
    await load(orderId);
  }

  Future<void> load(String orderId) async {
    _orderId = orderId;
    emit(const PatientOrderDetailLoading());
    final pharmacyResult = await _getMyPharmacy();
    _pharmacy = pharmacyResult.fold((_) => null, (pharmacy) => pharmacy);
    final result = await _get(orderId);
    await result.fold(
      (failure) async => emit(PatientOrderDetailError(failure.message)),
      (order) async {
        await _emitWithToken(order);
        await _subscription?.cancel();
        _subscription = _watch(orderId).listen(_onOrderChanged);
      },
    );
  }

  Future<void> _onOrderChanged(PharmacyOrder order) async {
    if (isClosed) return;
    await _emitWithToken(order);
  }

  /// Le QR n'existe que pour une commande prête : chaque affichage régénère
  /// le token (l'ancien est invalidé côté serveur). Le téléphone de la
  /// pharmacie n'est réutilisé que pour une commande refusée (bouton
  /// « Appeler la pharmacie » de la carte de refus, #5351).
  Future<void> _emitWithToken(PharmacyOrder order) async {
    if (order.status == PharmacyOrderStatus.rejected) {
      emit(PatientOrderDetailLoaded(
        order,
        pharmacy: _pharmacy,
        pharmacyPhone: _pharmacy?.phone,
      ));
      return;
    }
    if (!order.canShowPickupCode) {
      emit(PatientOrderDetailLoaded(order, pharmacy: _pharmacy));
      return;
    }
    final tokenResult = await _pickupToken(order.id);
    tokenResult.fold(
      (_) => emit(PatientOrderDetailLoaded(order, pharmacy: _pharmacy)),
      (token) => emit(PatientOrderDetailLoaded(order,
          pickupToken: token, pharmacy: _pharmacy)),
    );
  }

  Future<void> cancelOrder() async {
    final current = state;
    if (current is! PatientOrderDetailLoaded || current.cancelling) return;
    emit(PatientOrderDetailLoaded(current.order,
        cancelling: true, pharmacy: _pharmacy));
    final result = await _cancel(current.order.id);
    result.fold(
      (failure) => emit(PatientOrderDetailError(failure.message)),
      (order) => emit(PatientOrderDetailLoaded(order, pharmacy: _pharmacy)),
    );
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
