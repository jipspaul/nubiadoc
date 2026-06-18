import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/members/members_api.dart';
import 'package:nubia_domain/src/entities/member.dart';
import 'package:nubia_domain/src/repositories/members_repository.dart';

class MembersRepositoryImpl implements MembersRepository {
  final MembersApi _api;

  const MembersRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<Member>>> list() async {
    try {
      final dtos = await _api.list();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les membres.',
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, Member>> getById(String id) async {
    try {
      final dto = await _api.getById(id);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Membre introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger le membre.',
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, Member>> create(Member member) async {
    try {
      final dto = await _api.create(member);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de créer le membre.',
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, Member>> update(Member member) async {
    try {
      final dto = await _api.update(member);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Membre introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de mettre à jour le membre.',
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, Member>> invite(String email, MemberRole role) async {
    try {
      final dto = await _api.invite(email, role);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible d\'inviter le membre.',
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, Member>> updateRole(
      String id, MemberRole role) async {
    try {
      final dto = await _api.updateRole(id, role);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Membre introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de mettre à jour le rôle.',
        statusCode: e.response?.statusCode,
      ));
    }
  }
}
