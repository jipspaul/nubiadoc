import 'package:equatable/equatable.dart';

sealed class OrderDetailEvent extends Equatable {
  const OrderDetailEvent();

  @override
  List<Object?> get props => [];
}

class OrderDetailLoadRequested extends OrderDetailEvent {
  const OrderDetailLoadRequested(this.orderId);

  final String orderId;

  @override
  List<Object?> get props => [orderId];
}

/// received → preparing.
class OrderDetailAcceptRequested extends OrderDetailEvent {
  const OrderDetailAcceptRequested();
}

/// preparing → ready.
class OrderDetailReadyRequested extends OrderDetailEvent {
  const OrderDetailReadyRequested();
}

/// received → rejected (motif obligatoire).
class OrderDetailRejectRequested extends OrderDetailEvent {
  const OrderDetailRejectRequested(this.reason);

  final String reason;

  @override
  List<Object?> get props => [reason];
}

/// Ouvre le PDF d'ordonnance (URL signée).
class OrderDetailDocumentRequested extends OrderDetailEvent {
  const OrderDetailDocumentRequested();
}
