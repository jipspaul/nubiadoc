import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Action à l'origine de la résolution d'URL en cours (#5334) — distingue
/// l'ouverture directe (« Exporter cette fiche ») du partage natif
/// (« Partager avec un professionnel ») bien que les deux réutilisent le
/// même export ciblé côté domaine.
enum ImplantDetailAction { export, share }

sealed class ImplantDetailState extends Equatable {
  const ImplantDetailState();
  @override
  List<Object?> get props => [];
}

final class ImplantDetailIdle extends ImplantDetailState {
  const ImplantDetailIdle();
}

final class ImplantDetailLoading extends ImplantDetailState {
  final ImplantDetailAction action;
  const ImplantDetailLoading(this.action);
  @override
  List<Object?> get props => [action];
}

final class ImplantDetailUrlReady extends ImplantDetailState {
  final String url;
  final ImplantDetailAction action;
  const ImplantDetailUrlReady(this.url, this.action);
  @override
  List<Object?> get props => [url, action];
}

final class ImplantDetailError extends ImplantDetailState {
  final String message;
  const ImplantDetailError(this.message);
  @override
  List<Object?> get props => [message];
}

class ImplantDetailCubit extends Cubit<ImplantDetailState>
    with SafeEmitMixin<ImplantDetailState> {
  ImplantDetailCubit({required ExportImplantPassportUseCase export})
      : _export = export,
        super(const ImplantDetailIdle());

  final ExportImplantPassportUseCase _export;

  Future<void> exportImplant(String implantId) =>
      _resolveUrl(implantId, ImplantDetailAction.export);

  Future<void> shareImplant(String implantId) =>
      _resolveUrl(implantId, ImplantDetailAction.share);

  Future<void> _resolveUrl(String implantId, ImplantDetailAction action) async {
    safeEmit(ImplantDetailLoading(action));
    final result = await _export(implantId: implantId);
    result.fold(
      (f) => safeEmit(ImplantDetailError(f.message)),
      (url) => safeEmit(ImplantDetailUrlReady(url, action)),
    );
  }

  /// Repasse par un état neutre après consommation de l'URL — évite de
  /// rouvrir le lien / relancer le partage à chaque rebuild (même piège que
  /// `ImplantPassportCubit.export()`, cf. #4142).
  void reset() => safeEmit(const ImplantDetailIdle());
}
