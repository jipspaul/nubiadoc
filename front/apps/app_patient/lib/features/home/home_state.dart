import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class HomeState extends Equatable {
  const HomeState();

  @override
  List<Object?> get props => [];
}

final class HomeInitial extends HomeState {
  const HomeInitial();
}

final class HomeLoading extends HomeState {
  const HomeLoading();
}

final class HomeLoaded extends HomeState {
  final DashboardSummary summary;

  const HomeLoaded(this.summary);

  @override
  List<Object?> get props => [summary];
}

final class HomeError extends HomeState {
  final String message;

  const HomeError(this.message);

  @override
  List<Object?> get props => [message];
}
