import 'package:nubia_domain/nubia_domain.dart';

sealed class CabinetPayoutsState {
  const CabinetPayoutsState();
}

class CabinetPayoutsLoading extends CabinetPayoutsState {
  const CabinetPayoutsLoading();

  @override
  bool operator ==(Object other) => other is CabinetPayoutsLoading;

  @override
  int get hashCode => runtimeType.hashCode;
}

class CabinetPayoutsLoaded extends CabinetPayoutsState {
  const CabinetPayoutsLoaded(this.payouts);

  final List<CabinetPayout> payouts;

  @override
  bool operator ==(Object other) =>
      other is CabinetPayoutsLoaded &&
      other.payouts.length == payouts.length &&
      List.generate(
        payouts.length,
        (i) => other.payouts[i] == payouts[i],
      ).every((b) => b);

  @override
  int get hashCode => Object.hashAll(payouts);
}

class CabinetPayoutsError extends CabinetPayoutsState {
  const CabinetPayoutsError(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is CabinetPayoutsError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}
