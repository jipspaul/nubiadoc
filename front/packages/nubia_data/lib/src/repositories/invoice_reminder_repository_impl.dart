import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/invoice_reminder/invoice_reminder_api.dart';
import 'package:nubia_domain/src/entities/invoice_reminder.dart';
import 'package:nubia_domain/src/repositories/invoice_reminder_repository.dart';

class InvoiceReminderRepositoryImpl implements InvoiceReminderRepository {
  final InvoiceReminderApi _api;

  const InvoiceReminderRepositoryImpl(this._api);

  @override
  Future<Either<Failure, void>> send(String invoiceId) async {
    try {
      await _api.send(invoiceId);
      return const Right(null);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 404) {
        return const Left(NotFoundFailure('Facture introuvable.'));
      }
      if (code == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (code == 409) {
        return const Left(ServerFailure(
          message: 'Une relance a déjà été envoyée cette semaine.',
          statusCode: 409,
          code: 'invoice_reminder_cooldown',
        ));
      }
      return Left(ServerFailure(
        message: 'Envoi de la relance impossible.',
        statusCode: code,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, List<InvoiceReminder>>> listHistory(
    String invoiceId,
  ) async {
    try {
      final dtos = await _api.listHistory(invoiceId);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Facture introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de charger l'historique des relances.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
