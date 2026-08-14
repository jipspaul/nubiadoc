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

/// Garde-fou d'interface : le token est valide (le back l'accepte) mais la
/// commande renvoyée n'est pas celle en main du pharmacien — QR d'un autre
/// patient. Bloque la délivrance avant tout affichage de succès.
class PickupScanMismatch extends PickupScanState {
  const PickupScanMismatch({
    required this.expectedOrderId,
    required this.scannedOrder,
  });

  final String expectedOrderId;
  final PharmacyOrder scannedOrder;

  @override
  List<Object?> get props => [expectedOrderId, scannedOrder];
}

/// Cause précise d'un refus de scan — permet à l'UI d'afficher une conduite
/// distincte pour chacune des trois erreurs (#4884) plutôt qu'un texte
/// générique unique.
enum PickupScanInvalidCause {
  /// 404 — le code ne correspond à aucun token connu.
  unknownCode,

  /// 409 — le code est connu mais la commande n'est pas au bon statut.
  wrongStatus,

  /// 410 — le code était valide mais a expiré.
  expired,
}

/// Code refusé (409 statut, 410 expiré, 404 inconnu) — message actionnable.
class PickupScanInvalidCode extends PickupScanState {
  const PickupScanInvalidCode(this.message, this.cause);

  final String message;
  final PickupScanInvalidCause cause;

  @override
  List<Object?> get props => [message, cause];
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

  Future<void> submit(String token, {required String expectedOrderId}) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty || state is PickupScanSubmitting) return;

    emit(const PickupScanSubmitting());
    final result = await _confirmPickup(trimmed);
    result.fold(
      (failure) {
        final cause = _invalidCause(failure);
        if (cause != null) {
          emit(PickupScanInvalidCode(failure.message, cause));
        } else {
          emit(PickupScanError(failure.message));
        }
      },
      (order) {
        // Le token est bon (le back valide), mais rien côté back ne compare
        // la commande d'origine et celle du token — c'est ce garde-fou qui
        // interdit la délivrance d'un sachet au mauvais patient.
        if (order.id != expectedOrderId) {
          emit(PickupScanMismatch(
            expectedOrderId: expectedOrderId,
            scannedOrder: order,
          ));
        } else {
          emit(PickupScanSuccess(order));
        }
      },
    );
  }

  /// Repart pour un nouveau scan après un échec.
  void reset() => emit(const PickupScanIdle());

  /// 404/409/410 sont trois causes distinctes (#4884) — `null` pour les
  /// autres échecs (réseau, etc.), qui restent des `PickupScanError`.
  PickupScanInvalidCause? _invalidCause(Failure failure) {
    if (failure is NotFoundFailure) return PickupScanInvalidCause.unknownCode;
    if (failure is ServerFailure) {
      if (failure.statusCode == 409) return PickupScanInvalidCause.wrongStatus;
      if (failure.statusCode == 410) return PickupScanInvalidCause.expired;
    }
    return null;
  }
}
