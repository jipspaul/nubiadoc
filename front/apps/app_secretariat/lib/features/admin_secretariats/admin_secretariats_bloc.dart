import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'admin_secretariats_event.dart';
import 'admin_secretariats_state.dart';

class AdminSecretiariatsBloc
    extends Bloc<AdminSecretiariatsEvent, AdminSecretiariatsState>
    with SafeEmitMixin<AdminSecretiariatsState> {
  final ListSecretiariatsUseCase _listSecretariats;

  AdminSecretiariatsBloc({
    required ListSecretiariatsUseCase listSecretariats,
  })  : _listSecretariats = listSecretariats,
        super(const AdminSecretiariatsInitial()) {
    on<AdminSecretiariatsLoadRequested>(_onLoad);
  }

  Future<void> _onLoad(
    AdminSecretiariatsLoadRequested event,
    Emitter<AdminSecretiariatsState> emit,
  ) async {
    emit(const AdminSecretiariatsLoading());
    try {
      final result = await _listSecretariats();
      result.fold(
        (failure) => safeEmit(AdminSecretiariatsError(failure.message)),
        (secretariats) =>
            safeEmit(AdminSecretiariatsLoaded(secretariats: secretariats)),
      );
    } catch (_) {
      safeEmit(const AdminSecretiariatsError('Erreur de chargement.'));
    }
  }
}
