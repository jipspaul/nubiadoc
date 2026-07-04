import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../session/pro_auth_cubit.dart';

sealed class ProRegisterState extends Equatable {
  const ProRegisterState();

  @override
  List<Object?> get props => [];
}

final class ProRegisterIdle extends ProRegisterState {
  const ProRegisterIdle();
}

final class ProRegisterLoading extends ProRegisterState {
  const ProRegisterLoading();
}

final class ProRegisterSuccess extends ProRegisterState {
  final String accountId;
  const ProRegisterSuccess(this.accountId);

  @override
  List<Object?> get props => [accountId];
}

final class ProRegisterFailure extends ProRegisterState {
  final String message;
  const ProRegisterFailure(this.message);

  @override
  List<Object?> get props => [message];
}

class ProRegisterCubit extends Cubit<ProRegisterState>
    with SafeEmitMixin<ProRegisterState> {
  ProRegisterCubit({
    required ProRegisterUseCase register,
    required ProAuthCubit authCubit,
  })  : _register = register,
        _authCubit = authCubit,
        super(const ProRegisterIdle());

  final ProRegisterUseCase _register;
  final ProAuthCubit _authCubit;

  Future<void> submit(ProRegisterRequest request) async {
    emit(const ProRegisterLoading());
    try {
      final result = await _register(request);
      await result.fold(
        (failure) async => safeEmit(ProRegisterFailure(failure.message)),
        (accountId) async {
          await _authCubit.restore();
          safeEmit(ProRegisterSuccess(accountId));
        },
      );
    } catch (_) {
      safeEmit(
          const ProRegisterFailure('Erreur lors de la création du compte.'));
    }
  }
}
