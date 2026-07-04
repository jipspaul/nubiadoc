import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class ResetPasswordState extends Equatable {
  const ResetPasswordState();

  @override
  List<Object?> get props => [];
}

final class ResetPasswordIdle extends ResetPasswordState {
  const ResetPasswordIdle();
}

final class ResetPasswordLoading extends ResetPasswordState {
  const ResetPasswordLoading();
}

final class ResetPasswordSuccess extends ResetPasswordState {
  const ResetPasswordSuccess();
}

final class ResetPasswordFailure extends ResetPasswordState {
  final String message;
  const ResetPasswordFailure(this.message);

  @override
  List<Object?> get props => [message];
}

class ResetPasswordCubit extends Cubit<ResetPasswordState>
    with SafeEmitMixin<ResetPasswordState> {
  ResetPasswordCubit({required ResetPasswordUseCase resetPassword})
      : _resetPassword = resetPassword,
        super(const ResetPasswordIdle());

  final ResetPasswordUseCase _resetPassword;

  Future<void> submit(
      {required String token, required String newPassword}) async {
    emit(const ResetPasswordLoading());
    try {
      final result =
          await _resetPassword(token: token, newPassword: newPassword);
      result.fold(
        (failure) => safeEmit(ResetPasswordFailure(failure.message)),
        (_) => safeEmit(const ResetPasswordSuccess()),
      );
    } catch (_) {
      safeEmit(const ResetPasswordFailure(
          'Erreur lors de la réinitialisation du mot de passe.'));
    }
  }
}
