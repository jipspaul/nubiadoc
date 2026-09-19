import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/practitioner_kpis.dart';
import 'package:nubia_domain/src/repositories/practitioner_kpis_repository.dart';

class GetMyKpisUseCase {
  final PractitionerKpisRepository _repository;

  const GetMyKpisUseCase(this._repository);

  Future<Either<Failure, PractitionerKpis>> call({String? period}) =>
      _repository.getMyKpis(period: period);
}
