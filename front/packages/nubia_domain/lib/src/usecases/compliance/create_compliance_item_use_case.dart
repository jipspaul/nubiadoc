import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/compliance_repository.dart';

class CreateComplianceItemUseCase {
  final ComplianceRepository _repository;

  const CreateComplianceItemUseCase(this._repository);

  Future<Either<Failure, String>> call({
    required String kind,
    required String label,
    String? subjectUserId,
    String? equipmentLabel,
    required String dueDate,
    int? recurrenceMonths,
  }) =>
      _repository.createItem(
        kind: kind,
        label: label,
        subjectUserId: subjectUserId,
        equipmentLabel: equipmentLabel,
        dueDate: dueDate,
        recurrenceMonths: recurrenceMonths,
      );
}
