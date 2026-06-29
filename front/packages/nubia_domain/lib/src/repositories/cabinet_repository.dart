import 'package:dartz/dartz.dart';
import '../error/failure.dart';

class UpdateCabinetRequest {
  final String? name;
  final String? address;
  final String? phone;
  final String? siret;

  const UpdateCabinetRequest({
    this.name,
    this.address,
    this.phone,
    this.siret,
  });
}

abstract class CabinetRepository {
  Future<Either<Failure, void>> updateCabinet(UpdateCabinetRequest request);
}
