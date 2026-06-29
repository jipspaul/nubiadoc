import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class AccountSetupState extends Equatable {
  const AccountSetupState();

  @override
  List<Object?> get props => [];
}

final class AccountSetupIdle extends AccountSetupState {
  const AccountSetupIdle();
}

final class AccountSetupLoading extends AccountSetupState {
  const AccountSetupLoading();
}

final class AccountSetupSuccess extends AccountSetupState {
  const AccountSetupSuccess();
}

final class AccountSetupFailure extends AccountSetupState {
  final String message;
  const AccountSetupFailure(this.message);

  @override
  List<Object?> get props => [message];
}

class AccountSetupCubit extends Cubit<AccountSetupState>
    with SafeEmitMixin<AccountSetupState> {
  AccountSetupCubit({required UpdateAccountUseCase updateAccount})
      : _updateAccount = updateAccount,
        super(const AccountSetupIdle());

  final UpdateAccountUseCase _updateAccount;

  Future<void> submit({
    required String firstName,
    required String lastName,
    required String phone,
    required DateTime dateOfBirth,
  }) async {
    emit(const AccountSetupLoading());
    final result = await _updateAccount(
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      dateOfBirth: dateOfBirth,
    );
    result.fold(
      (failure) => safeEmit(AccountSetupFailure(failure.message)),
      (_) => safeEmit(const AccountSetupSuccess()),
    );
  }
}
