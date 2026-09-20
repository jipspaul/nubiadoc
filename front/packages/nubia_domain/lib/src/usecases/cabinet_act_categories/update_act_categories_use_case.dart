import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/act_category_setting.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_act_categories_repository.dart';

class UpdateActCategoriesUseCase {
  final CabinetActCategoriesRepository _repository;

  const UpdateActCategoriesUseCase(this._repository);

  Future<Either<Failure, List<ActCategorySetting>>> call(
    List<ActCategorySetting> categories,
  ) {
    return _repository.updateActCategories(categories);
  }
}
