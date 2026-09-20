import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/act_category_setting.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_act_categories_repository.dart';

class GetActCategoriesUseCase {
  final CabinetActCategoriesRepository _repository;

  const GetActCategoriesUseCase(this._repository);

  Future<Either<Failure, List<ActCategorySetting>>> call() {
    return _repository.getActCategories();
  }
}
