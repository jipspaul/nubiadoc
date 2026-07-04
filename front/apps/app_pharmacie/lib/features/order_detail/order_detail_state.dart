import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class OrderDetailState extends Equatable {
  const OrderDetailState();

  @override
  List<Object?> get props => [];
}

class OrderDetailLoading extends OrderDetailState {
  const OrderDetailLoading();
}

class OrderDetailLoaded extends OrderDetailState {
  const OrderDetailLoaded(this.order, {this.actionInProgress = false});

  final PharmacyOrder order;

  /// Une transition est en cours (bouton en loading, double-tap bloqué).
  final bool actionInProgress;

  @override
  List<Object?> get props => [order, actionInProgress];
}

/// L'URL signée du PDF est prête — la page l'ouvre puis revient à Loaded.
class OrderDetailDocumentReady extends OrderDetailState {
  const OrderDetailDocumentReady(this.order, this.url);

  final PharmacyOrder order;
  final String url;

  @override
  List<Object?> get props => [order, url];
}

class OrderDetailError extends OrderDetailState {
  const OrderDetailError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
