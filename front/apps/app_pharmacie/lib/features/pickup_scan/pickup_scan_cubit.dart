import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class PickupScanState extends Equatable {
  const PickupScanState();

  @override
  List<Object?> get props => [];
}

class PickupScanIdle extends PickupScanState {
  const PickupScanIdle();
}

class PickupScanSubmitting extends PickupScanState {
  const PickupScanSubmitting();
}

class PickupScanSuccess extends PickupScanState {
  const PickupScanSuccess(this.order);

  final PharmacyOrder order;

  @override
  List<Object?> get props => [order];
}

/// Code refusé (409 statut, 410 expiré, 404 inconnu) — message actionnable.
class PickupScanInvalidCode extends PickupScanState {
  const PickupScanInvalidCode(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class PickupScanError extends PickupScanState {
  const PickupScanError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Validation du retrait par le token du QR patient (scan caméra ou saisie
/// manuelle — le backend ne voit qu'un token, jamais la provenance).
class PickupScanCubit extends Cubit<PickupScanState> {
  PickupScanCubit({required ConfirmPharmacyPickupUseCase confirmPickup})
      : _confirmPickup = confirmPickup,
        super(const PickupScanIdle());

  final ConfirmPharmacyPickupUseCase _confirmPickup;

  Future<void> submit(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty || state is PickupScanSubmitting) return;

    emit(const PickupScanSubmitting());
    final result = await _confirmPickup(trimmed);
    result.fold(
      (failure) {
        final invalid = failure is NotFoundFailure ||
            (failure is ServerFailure &&
                (failure.statusCode == 409 || failure.statusCode == 410));
        if (invalid) {
          emit(PickupScanInvalidCode(failure.message));
        } else {
          emit(PickupScanError(failure.message));
        }
      },
      (order) => emit(PickupScanSuccess(order)),
    );
  }

  /// Repart pour un nouveau scan après un échec.
  void reset() => emit(const PickupScanIdle());
}
