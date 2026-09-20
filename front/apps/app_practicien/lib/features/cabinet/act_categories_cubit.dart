import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Catégorie retenue par le preset « cabinet 100% ortho » (#7185) — seule
/// `ortho` reste activée, toutes les autres sont masquées du catalogue
/// (`GET /v1/ccam/acts`, #7186) et donc de la consultation clinique.
const kFullOrthoCategory = 'ortho';

sealed class ActCategoriesState extends Equatable {
  const ActCategoriesState();
  @override
  List<Object?> get props => [];
}

final class ActCategoriesLoading extends ActCategoriesState {
  const ActCategoriesLoading();
}

final class ActCategoriesLoaded extends ActCategoriesState {
  final List<ActCategorySetting> categories;
  final bool saving;
  const ActCategoriesLoaded(this.categories, {this.saving = false});

  @override
  List<Object?> get props => [categories, saving];
}

final class ActCategoriesError extends ActCategoriesState {
  final String message;
  const ActCategoriesError(this.message);

  @override
  List<Object?> get props => [message];
}

/// Réglage cabinet des catégories d'actes CCAM activées (#7185/#7186) —
/// écran praticien d'`GET/PUT /v1/cabinet/settings/act-categories`, avec un
/// preset « cabinet 100% ortho » qui masque en un geste toutes les
/// catégories non pratiquées.
class ActCategoriesCubit extends Cubit<ActCategoriesState>
    with SafeEmitMixin<ActCategoriesState> {
  ActCategoriesCubit({
    required GetActCategoriesUseCase get,
    required UpdateActCategoriesUseCase update,
  })  : _get = get,
        _update = update,
        super(const ActCategoriesLoading());

  final GetActCategoriesUseCase _get;
  final UpdateActCategoriesUseCase _update;

  Future<void> load() async {
    emit(const ActCategoriesLoading());
    final result = await _get();
    result.fold(
      (f) => safeEmit(ActCategoriesError(f.message)),
      (categories) => safeEmit(ActCategoriesLoaded(categories)),
    );
  }

  Future<void> toggle(String category, bool enabled) async {
    final current = state;
    if (current is! ActCategoriesLoaded) return;
    final previous = current.categories;
    final updated = [
      for (final c in previous)
        c.category == category ? c.copyWith(enabled: enabled) : c,
    ];
    await _save(updated, previous);
  }

  /// Preset « cabinet 100% ortho » : n'active que [kFullOrthoCategory].
  Future<void> applyFullOrthoPreset() async {
    final current = state;
    if (current is! ActCategoriesLoaded) return;
    final previous = current.categories;
    final updated = [
      for (final c in previous)
        c.copyWith(enabled: c.category == kFullOrthoCategory),
    ];
    await _save(updated, previous);
  }

  /// Applique un changement optimiste et persiste ; rollback sur échec.
  Future<void> _save(
    List<ActCategorySetting> updated,
    List<ActCategorySetting> previous,
  ) async {
    emit(ActCategoriesLoaded(updated, saving: true));
    final result = await _update(updated);
    result.fold(
      (f) {
        safeEmit(ActCategoriesError(f.message));
        safeEmit(ActCategoriesLoaded(previous));
      },
      (saved) => safeEmit(ActCategoriesLoaded(saved)),
    );
  }
}
