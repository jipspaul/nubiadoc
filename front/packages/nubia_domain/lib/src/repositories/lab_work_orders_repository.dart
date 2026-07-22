import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/lab_work_order.dart';

abstract class LabWorkOrdersRepository {
  /// GET /v1/cabinet/lab-work-orders (#4149), du plus récent au plus ancien.
  Future<Either<Failure, List<LabWorkOrder>>> listOrders();

  /// PATCH /v1/cabinet/lab-work-orders/:id (#4149). Renvoie le nouveau statut.
  Future<Either<Failure, String>> updateStatus(String orderId, String status);
}
