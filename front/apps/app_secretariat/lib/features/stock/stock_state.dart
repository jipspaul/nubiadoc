import 'package:nubia_domain/nubia_domain.dart';

sealed class StockState {
  const StockState();
}

class StockLoading extends StockState {
  const StockLoading();

  @override
  bool operator ==(Object other) => other is StockLoading;

  @override
  int get hashCode => runtimeType.hashCode;
}

class StockLoaded extends StockState {
  const StockLoaded(this.requests, {this.creating = false, this.resendingId});

  final List<StockRequest> requests;

  /// Envoi d'une nouvelle demande en cours (bouton en loading).
  final bool creating;

  /// Demande dont la relance est en cours (bouton en loading) — #5183.
  final String? resendingId;

  @override
  bool operator ==(Object other) =>
      other is StockLoaded &&
      other.creating == creating &&
      other.resendingId == resendingId &&
      other.requests.length == requests.length &&
      List.generate(
        requests.length,
        (i) => other.requests[i] == requests[i],
      ).every((b) => b);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(requests), creating, resendingId);
}

class StockError extends StockState {
  const StockError(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is StockError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}
