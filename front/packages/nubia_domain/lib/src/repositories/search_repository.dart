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

  Future<Either<Failure, Slot>> holdSlot(String slotId);
}
