import 'package:dartz/dartz.dart';
import '../entities/act_category_setting.dart';
import '../error/failure.dart';

abstract class CabinetActCategoriesRepository {
  Future<Either<Failure, List<ActCategorySetting>>> getActCategories();

  Future<Either<Failure, List<ActCategorySetting>>> updateActCategories(
    List<ActCategorySetting> categories,
  );
}
