import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class OrdersState extends Equatable {
  const OrdersState();

  @override
  List<Object?> get props => [];
}

class OrdersLoading extends OrdersState {
  const OrdersLoading();
}

class OrdersLoaded extends OrdersState {
  const OrdersLoaded({required this.orders, this.filter});

  /// File complète (non filtrée) — le filtre s'applique à l'affichage.
  final List<PharmacyOrder> orders;
  final PharmacyOrderStatus? filter;

  List<PharmacyOrder> get visible => filter == null
      ? orders
      : orders.where((order) => order.status == filter).toList();

  @override
  List<Object?> get props => [orders, filter];
}

class OrdersError extends OrdersState {
  const OrdersError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
