import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class CabinetInfoState extends Equatable {
  const CabinetInfoState();

  @override
  List<Object?> get props => [];
}

final class CabinetInfoIdle extends CabinetInfoState {
  const CabinetInfoIdle();
}

final class CabinetInfoLoading extends CabinetInfoState {
  const CabinetInfoLoading();
}

final class CabinetInfoSuccess extends CabinetInfoState {
  const CabinetInfoSuccess();
}

final class CabinetInfoFailure extends CabinetInfoState {
  final String message;
  const CabinetInfoFailure(this.message);

  @override
  List<Object?> get props => [message];
}

class CabinetInfoCubit extends Cubit<CabinetInfoState>
    with SafeEmitMixin<CabinetInfoState> {
  CabinetInfoCubit({required UpdateCabinetUseCase updateCabinet})
      : _updateCabinet = updateCabinet,
        super(const CabinetInfoIdle());

  final UpdateCabinetUseCase _updateCabinet;

  Future<void> submit({
    required String name,
    required String address,
    required String phone,
    String? siret,
  }) async {
    emit(const CabinetInfoLoading());
    final result = await _updateCabinet(
      UpdateCabinetRequest(
        name: name,
        address: address,
        phone: phone,
        siret: siret?.isEmpty == true ? null : siret,
      ),
    );
    result.fold(
      (failure) => safeEmit(CabinetInfoFailure(failure.message)),
      (_) => safeEmit(const CabinetInfoSuccess()),
    );
  }
}
