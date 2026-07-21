import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/prescription_template.dart';
import 'package:nubia_domain/src/repositories/prescription_repository.dart';

class ListPrescriptionTemplatesUseCase {
  final PrescriptionRepository _repository;

  const ListPrescriptionTemplatesUseCase(this._repository);

  Future<Either<Failure, List<PrescriptionTemplate>>> call() =>
      _repository.listPrescriptionTemplates();
}
