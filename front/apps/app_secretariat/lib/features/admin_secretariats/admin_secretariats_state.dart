import 'package:nubia_domain/nubia_domain.dart';

abstract class AdminSecretiariatsState {
  const AdminSecretiariatsState();
}

class AdminSecretiariatsInitial extends AdminSecretiariatsState {
  const AdminSecretiariatsInitial();

  @override
  bool operator ==(Object other) => other is AdminSecretiariatsInitial;

  @override
  int get hashCode => runtimeType.hashCode;
}

class AdminSecretiariatsLoading extends AdminSecretiariatsState {
  const AdminSecretiariatsLoading();

  @override
  bool operator ==(Object other) => other is AdminSecretiariatsLoading;

  @override
  int get hashCode => runtimeType.hashCode;
}

class AdminSecretiariatsLoaded extends AdminSecretiariatsState {
  const AdminSecretiariatsLoaded({required this.secretariats});

  final List<Secretariat> secretariats;

  @override
  bool operator ==(Object other) =>
      other is AdminSecretiariatsLoaded &&
      other.secretariats.length == secretariats.length;

  @override
  int get hashCode => secretariats.length.hashCode;
}

class AdminSecretiariatsError extends AdminSecretiariatsState {
  const AdminSecretiariatsError(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is AdminSecretiariatsError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}
