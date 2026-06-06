import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/domain/repositories/account_repository.dart';
import 'package:nubia_patient/presentation/features/account/bloc/account_event.dart';
import 'package:nubia_patient/presentation/features/account/bloc/account_state.dart';

@injectable
class AccountBloc extends Bloc<AccountEvent, AccountState> {
  final AccountRepository _repository;

  AccountBloc(this._repository) : super(const AccountInitial()) {
    on<AccountLoadRequested>(_onLoadRequested);
    on<AccountUpdateRequested>(_onUpdateRequested);
    on<AccountCoverageLoadRequested>(_onCoverageLoadRequested);
    on<AccountCoverageUpdateRequested>(_onCoverageUpdateRequested);
    on<AccountDependentsLoadRequested>(_onDependentsLoadRequested);
    on<AccountDependentAddRequested>(_onDependentAddRequested);
    on<AccountDependentDeleteRequested>(_onDependentDeleteRequested);
  }

  Future<void> _onLoadRequested(
    AccountLoadRequested event,
    Emitter<AccountState> emit,
  ) async {
    emit(const AccountLoading());
    final result = await _repository.getAccount();
    result.fold(
      (failure) => emit(AccountError(failure.message)),
      (account) => emit(AccountLoaded(account)),
    );
  }

  Future<void> _onUpdateRequested(
    AccountUpdateRequested event,
    Emitter<AccountState> emit,
  ) async {
    emit(const AccountUpdating());
    final result = await _repository.updateAccount(
      firstName: event.firstName,
      lastName: event.lastName,
      phone: event.phone,
    );
    result.fold(
      (failure) => emit(AccountError(failure.message)),
      (account) => emit(AccountUpdated(account)),
    );
  }

  Future<void> _onCoverageLoadRequested(
    AccountCoverageLoadRequested event,
    Emitter<AccountState> emit,
  ) async {
    emit(const AccountCoverageLoading());
    final result = await _repository.getCoverage();
    result.fold(
      (failure) => emit(AccountCoverageError(failure.message)),
      (coverage) => emit(AccountCoverageLoaded(coverage)),
    );
  }

  Future<void> _onCoverageUpdateRequested(
    AccountCoverageUpdateRequested event,
    Emitter<AccountState> emit,
  ) async {
    final current = state;
    if (current is AccountCoverageLoaded) {
      emit(AccountCoverageUpdating(current.coverage));
    }
    final result = await _repository.updateCoverage(
      regime: event.regime,
      amc: event.amc,
      numeroAdherent: event.numeroAdherent,
      thirdPartyPayment: event.thirdPartyPayment,
    );
    result.fold(
      (failure) => emit(AccountCoverageError(failure.message)),
      (coverage) => emit(AccountCoverageUpdated(coverage)),
    );
  }

  Future<void> _onDependentsLoadRequested(
    AccountDependentsLoadRequested event,
    Emitter<AccountState> emit,
  ) async {
    emit(const AccountDependentsLoading());
    final result = await _repository.getDependents();
    result.fold(
      (failure) => emit(AccountDependentsError(failure.message)),
      (dependents) => emit(AccountDependentsLoaded(dependents)),
    );
  }

  Future<void> _onDependentAddRequested(
    AccountDependentAddRequested event,
    Emitter<AccountState> emit,
  ) async {
    final result = await _repository.addDependent(
      firstName: event.firstName,
      lastName: event.lastName,
      birthDate: event.birthDate,
      relationship: event.relationship,
    );
    await result.fold(
      (failure) async => emit(AccountDependentsError(failure.message)),
      (added) async {
        final listResult = await _repository.getDependents();
        listResult.fold(
          (failure) => emit(AccountDependentsError(failure.message)),
          (dependents) => emit(AccountDependentAdded(dependents)),
        );
      },
    );
  }

  Future<void> _onDependentDeleteRequested(
    AccountDependentDeleteRequested event,
    Emitter<AccountState> emit,
  ) async {
    final result = await _repository.deleteDependent(event.id);
    await result.fold(
      (failure) async => emit(AccountDependentsError(failure.message)),
      (_) async {
        final listResult = await _repository.getDependents();
        listResult.fold(
          (failure) => emit(AccountDependentsError(failure.message)),
          (dependents) => emit(AccountDependentsLoaded(dependents)),
        );
      },
    );
  }
}
