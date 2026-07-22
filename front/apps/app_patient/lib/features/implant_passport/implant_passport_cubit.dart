import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class ImplantPassportState extends Equatable {
  const ImplantPassportState();
  @override
  List<Object?> get props => [];
}

final class ImplantPassportLoading extends ImplantPassportState {
  const ImplantPassportLoading();
}

final class ImplantPassportLoaded extends ImplantPassportState {
  final List<ImplantItem> implants;

  /// URL signée résolue par un export en cours (déclenche l'ouverture externe).
  final String? exportUrl;
  const ImplantPassportLoaded(this.implants, {this.exportUrl});
  @override
  List<Object?> get props => [implants, exportUrl];
}

final class ImplantPassportError extends ImplantPassportState {
  final String message;
  const ImplantPassportError(this.message);
  @override
  List<Object?> get props => [message];
}

class ImplantPassportCubit extends Cubit<ImplantPassportState>
    with SafeEmitMixin<ImplantPassportState> {
  ImplantPassportCubit({
    required ListImplantPassportUseCase list,
    required ExportImplantPassportUseCase export,
  })  : _list = list,
        _export = export,
        super(const ImplantPassportLoading());

  final ListImplantPassportUseCase _list;
  final ExportImplantPassportUseCase _export;

  Future<void> load() async {
    emit(const ImplantPassportLoading());
    final result = await _list();
    result.fold(
      (f) => safeEmit(ImplantPassportError(f.message)),
      (implants) => safeEmit(ImplantPassportLoaded(implants)),
    );
  }

  Future<void> export() async {
    final current = state;
    if (current is! ImplantPassportLoaded) return;
    final result = await _export();
    result.fold(
      (f) => safeEmit(ImplantPassportError(f.message)),
      (url) =>
          safeEmit(ImplantPassportLoaded(current.implants, exportUrl: url)),
    );
  }
}
