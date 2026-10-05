import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/lab_work_orders_repository.dart';

class CreateLabWorkOrderUseCase {
  final LabWorkOrdersRepository _repository;

  const CreateLabWorkOrderUseCase(this._repository);

  Future<Either<Failure, String>> call({
    required String patientId,
    required String labName,
    required int purchasePriceCents,
    String? expectedReturnAt,
  }) =>
      _repository.createOrder(
        patientId: patientId,
        labName: labName,
        purchasePriceCents: purchasePriceCents,
        expectedReturnAt: expectedReturnAt,
      );
}
