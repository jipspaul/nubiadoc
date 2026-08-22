import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class IncomingRequestState extends Equatable {
  const IncomingRequestState();
  @override
  List<Object?> get props => [];
}

final class IncomingRequestLoading extends IncomingRequestState {
  const IncomingRequestLoading();
}

final class IncomingRequestLoaded extends IncomingRequestState {
  final AccessRequest request;
  final Set<AccessRight> scope;
  final bool mutating;
  final String? errorMessage;

  const IncomingRequestLoaded(
    this.request, {
    required this.scope,
    this.mutating = false,
    this.errorMessage,
  });

  @override
  List<Object?> get props => [request, scope, mutating, errorMessage];
}

/// Décision de l'invité sur une [AccessRequest] reçue (« Décider », #5258).
///
/// Distinct de [DependentsCubit] : ici l'utilisateur courant est l'invité,
/// pas le gestionnaire. `scope` porte le périmètre ajusté avant acceptation
/// (#5257) ; par défaut le périmètre proposé par le demandeur.
class IncomingRequestCubit extends Cubit<IncomingRequestState>
    with SafeEmitMixin<IncomingRequestState> {
  IncomingRequestCubit({
    required AcceptAccessRequestUseCase accept,
    required RefuseAccessRequestUseCase refuse,
  })  : _accept = accept,
        _refuse = refuse,
        super(const IncomingRequestLoading());

  final AcceptAccessRequestUseCase _accept;
  final RefuseAccessRequestUseCase _refuse;

  void load(AccessRequest request) {
    emit(IncomingRequestLoaded(request, scope: request.grantedScope));
  }

  Future<void> accept(Set<AccessRight> scope) async {
    final current = state;
    if (current is! IncomingRequestLoaded) return;
    emit(IncomingRequestLoaded(current.request, scope: scope, mutating: true));
    final result = await _accept(current.request.id);
    result.fold(
      (f) => safeEmit(IncomingRequestLoaded(current.request,
          scope: scope, errorMessage: f.message)),
      (updated) => safeEmit(IncomingRequestLoaded(updated, scope: scope)),
    );
  }

  Future<void> refuse() async {
    final current = state;
    if (current is! IncomingRequestLoaded) return;
    emit(IncomingRequestLoaded(current.request,
        scope: current.scope, mutating: true));
    final result = await _refuse(current.request.id);
    result.fold(
      (f) => safeEmit(IncomingRequestLoaded(current.request,
          scope: current.scope, errorMessage: f.message)),
      (updated) =>
          safeEmit(IncomingRequestLoaded(updated, scope: current.scope)),
    );
  }
}
