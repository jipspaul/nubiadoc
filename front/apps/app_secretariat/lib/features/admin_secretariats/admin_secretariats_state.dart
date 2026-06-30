import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class AdminSecretiariatsState extends Equatable {
  const AdminSecretiariatsState();

  @override
  List<Object?> get props => [];
}

final class AdminSecretiariatsInitial extends AdminSecretiariatsState {
  const AdminSecretiariatsInitial();
}

final class AdminSecretiariatsLoading extends AdminSecretiariatsState {
  const AdminSecretiariatsLoading();
}

final class AdminSecretiariatsEmpty extends AdminSecretiariatsState {
  const AdminSecretiariatsEmpty();
}

final class AdminSecretiariatsLoaded extends AdminSecretiariatsState {
  const AdminSecretiariatsLoaded({required this.secretariats});

  final List<Secretariat> secretariats;

  @override
  List<Object?> get props => [secretariats];
}

final class AdminSecretiariatsError extends AdminSecretiariatsState {
  const AdminSecretiariatsError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
