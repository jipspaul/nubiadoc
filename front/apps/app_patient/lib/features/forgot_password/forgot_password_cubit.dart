import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class ForgotPasswordState extends Equatable {
  const ForgotPasswordState();

  @override
  List<Object?> get props => [];
}

final class ForgotPasswordIdle extends ForgotPasswordState {
  const ForgotPasswordIdle();
}

final class ForgotPasswordLoading extends ForgotPasswordState {
  const ForgotPasswordLoading();
}

final class ForgotPasswordSent extends ForgotPasswordState {
  const ForgotPasswordSent();
}

final class ForgotPasswordFailure extends ForgotPasswordState {
  final String message;
  const ForgotPasswordFailure(this.message);

  @override
  List<Object?> get props => [message];
}

class ForgotPasswordCubit extends Cubit<ForgotPasswordState>
    with SafeEmitMixin<ForgotPasswordState> {
  ForgotPasswordCubit({required ForgotPasswordUseCase forgotPassword})
      : _forgotPassword = forgotPassword,
        super(const ForgotPasswordIdle());

  final ForgotPasswordUseCase _forgotPassword;

  Future<void> submit(String email) async {
    emit(const ForgotPasswordLoading());
    try {
      final result = await _forgotPassword(email: email);
      result.fold(
        (failure) => safeEmit(ForgotPasswordFailure(failure.message)),
        (_) => safeEmit(const ForgotPasswordSent()),
      );
    } catch (_) {
      safeEmit(const ForgotPasswordFailure('Erreur lors de la demande.'));
    }
  }
}
