import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/provider_result.dart';
import 'package:nubia_domain/src/entities/slot.dart';
import 'package:nubia_domain/src/error/failure.dart';

abstract class SearchRepository {
  Future<Either<Failure, List<ProviderResult>>> searchProviders({
    required String query,
  });

  Future<Either<Failure, List<Slot>>> searchSlots({
    required String providerId,
    DateTime? from,
    DateTime? to,
  });

  /// Bloque un créneau 5 min ; retourne le hold_token.
  Future<Either<Failure, String>> holdSlot(String slotId);

  /// Confirme la réservation d'un créneau tenu via [holdSlot] (POST
  /// /v1/bookings, `docs/12-api-reference.md` §12.3). Retourne l'identifiant
  /// du rendez-vous créé.
  Future<Either<Failure, String>> confirmBooking({
    required String slotId,
    required String holdToken,
    required String motif,
    required String idempotencyKey,
  });
}
