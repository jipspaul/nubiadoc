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

  /// Message d'échec du dernier export : transitoire, la liste reste affichée.
  final String? exportError;
  const ImplantPassportLoaded(this.implants,
      {this.exportUrl, this.exportError});
  @override
  List<Object?> get props => [implants, exportUrl, exportError];
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
    // Efface tout signal transitoire d'un essai précédent, pour garantir que
    // le résultat de ce nouvel essai (même message d'erreur) déclenche bien
    // le listener plutôt que d'être ignoré comme un état identique.
    if (current.exportUrl != null || current.exportError != null) {
      safeEmit(ImplantPassportLoaded(current.implants));
    }
    final result = await _export();
    final base = state;
    if (base is! ImplantPassportLoaded) return;
    result.fold(
      (f) => safeEmit(
          ImplantPassportLoaded(base.implants, exportError: f.message)),
      (url) => safeEmit(ImplantPassportLoaded(base.implants, exportUrl: url)),
    );
  }
}
