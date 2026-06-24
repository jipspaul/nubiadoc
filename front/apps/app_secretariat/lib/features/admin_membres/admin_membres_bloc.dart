import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'admin_membres_event.dart';
import 'admin_membres_state.dart';

class AdminMembresBloc extends Bloc<AdminMembresEvent, AdminMembresState> {
  final ListMembersUseCase _listMembers;
  final ListSecretiariatsUseCase _listSecretariats;

  AdminMembresBloc({
    required ListMembersUseCase listMembers,
    required ListSecretiariatsUseCase listSecretariats,
  })  : _listMembers = listMembers,
        _listSecretariats = listSecretariats,
        super(const AdminMembresInitial()) {
    on<AdminMembresLoadRequested>(_onLoad);
  }

  Future<void> _onLoad(
    AdminMembresLoadRequested event,
    Emitter<AdminMembresState> emit,
  ) async {
    emit(const AdminMembresLoading());
    try {
      final membersResult = await _listMembers();
      final secretariatsResult = await _listSecretariats();

      final failure = membersResult.fold((f) => f, (_) => null) ??
          secretariatsResult.fold((f) => f, (_) => null);

      if (failure != null) {
        emit(AdminMembresError(failure.message));
        return;
      }

      emit(AdminMembresLoaded(
        members: membersResult.getOrElse(() => []),
        secretariats: secretariatsResult.getOrElse(() => []),
      ));
    } catch (_) {
      emit(const AdminMembresError('Erreur de chargement.'));
    }
  }
}
