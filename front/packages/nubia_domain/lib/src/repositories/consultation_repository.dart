import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/consultation_context.dart';

abstract class ConsultationRepository {
  Future<Either<Failure, List<ConsultationContext>>> list({int page = 1});
  Future<Either<Failure, ConsultationContext>> getById(String id);
  Future<Either<Failure, ConsultationContext>> create(
      ConsultationContext consultation);
  Future<Either<Failure, ConsultationContext>> update(
      ConsultationContext consultation);
}
