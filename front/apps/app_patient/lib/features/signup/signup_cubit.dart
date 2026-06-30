import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../session/auth_cubit.dart';

sealed class SignupState extends Equatable {
  const SignupState();

  @override
  List<Object?> get props => [];
}

final class SignupIdle extends SignupState {
  const SignupIdle();
}

final class SignupLoading extends SignupState {
  const SignupLoading();
}

final class SignupSuccess extends SignupState {
  const SignupSuccess();
}

final class SignupFailure extends SignupState {
  final String message;
  const SignupFailure(this.message);

  @override
  List<Object?> get props => [message];
}

const _kCguVersion = '1.0';

class SignupCubit extends Cubit<SignupState> with SafeEmitMixin<SignupState> {
  SignupCubit({
    required RegisterUseCase register,
    required AuthCubit authCubit,
  })  : _register = register,
        _authCubit = authCubit,
        super(const SignupIdle());

  final RegisterUseCase _register;
  final AuthCubit _authCubit;

  Future<void> register(
    String email,
    String password, {
    required bool acceptCgu,
  }) async {
    emit(const SignupLoading());
    try {
      final result = await _register(
        email: email,
        password: password,
        acceptCgu: acceptCgu,
        cguVersion: _kCguVersion,
      );
      await result.fold(
        (failure) async => safeEmit(SignupFailure(failure.message)),
        (_) async {
          await _authCubit.restore();
          safeEmit(const SignupSuccess());
        },
      );
    } catch (_) {
      safeEmit(const SignupFailure('Erreur lors de la création du compte.'));
    }
  }
}
