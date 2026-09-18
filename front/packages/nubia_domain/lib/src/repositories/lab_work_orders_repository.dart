import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/lab_work_order.dart';
import 'package:nubia_domain/src/entities/today_lab_work_order.dart';

abstract class LabWorkOrdersRepository {
  /// GET /v1/cabinet/lab-work-orders (#4149), du plus récent au plus ancien.
  Future<Either<Failure, List<LabWorkOrder>>> listOrders();

  /// GET /v1/cabinet/lab-work-orders/today (#7208) : bons dont le RDV de pose
  /// tombe aujourd'hui ou demain, triés par heure de RDV.
  Future<Either<Failure, List<TodayLabWorkOrder>>> todayOrders();

  /// PATCH /v1/cabinet/lab-work-orders/:id (#4149). Renvoie le nouveau statut.
  Future<Either<Failure, String>> updateStatus(String orderId, String status);
}
