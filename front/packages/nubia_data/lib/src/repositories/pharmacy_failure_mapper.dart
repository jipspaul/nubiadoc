import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_data/src/remote/pharmacy_orders/pharmacy_order_dto.dart';
import 'package:nubia_domain/src/error/failure.dart';

/// Mapping d'erreurs commun aux repos pharmacie.
///
/// 401 → session expirée ; 404 → introuvable (anti-énumération côté back) ;
/// 409 → transition/action invalide (machine à états serveur), ou
/// `pickup_order_mismatch` (#6349 : token valide mais mauvaise commande,
/// AUCUNE transition côté serveur) ; 410 → token de retrait expiré.
Future<Either<Failure, T>> guardPharmacyCall<T>(
  Future<T> Function() call, {
  required String errorMessage,
}) async {
  try {
    return Right(await call());
  } on DioException catch (e) {
    final status = e.response?.statusCode;
    switch (status) {
      case 401:
        return const Left(UnauthorizedFailure());
      case 404:
        return const Left(NotFoundFailure());
      case 409:
        final data = e.response?.data;
        if (data is Map && data['code'] == 'pickup_order_mismatch') {
          final orderJson = data['order'];
          if (orderJson is Map<String, dynamic>) {
            return Left(
              PickupOrderMismatchFailure(
                PharmacyOrderDto.fromJson(orderJson).toDomain(),
              ),
            );
          }
        }
        return const Left(
          ServerFailure(
            message: 'Action impossible dans l’état actuel de la commande.',
            statusCode: 409,
            code: 'invalid_status',
          ),
        );
      case 410:
        return const Left(
          ServerFailure(
            message: 'Ce code de retrait a expiré. Demandez au patient '
                'd’actualiser son QR code.',
            statusCode: 410,
            code: 'token_expired',
          ),
        );
      default:
        return Left(ServerFailure(message: errorMessage, statusCode: status));
    }
  } catch (_) {
    return const Left(ParseFailure());
  }
}
