import 'package:dartz/dartz.dart' hide State;
import 'package:flutter/widgets.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Centralise le triptyque chargement / erreur / retry commun aux cartes du
/// dossier patient (étiquettes, orthodontie, documents, questionnaire, #4973)
/// — un seul point de déclenchement du chargement au lieu de cinq `initState`
/// qui réimplémentent chacun la même logique.
mixin AsyncSectionState<T, W extends StatefulWidget> on State<W> {
  T? data;
  String? error;
  bool loading = true;

  /// #6426 — 403 déterministe (garde « relation de soin » RLS §14) :
  /// distinct d'une panne transitoire (500/timeout), un « Réessayer » ne
  /// peut structurellement jamais aboutir dans ce cas.
  bool accessDenied = false;

  Future<Either<Failure, T>> fetchSection();

  @override
  void initState() {
    super.initState();
    _fetchAndApply();
  }

  /// Recharge la section — utilisé au chargement initial, après une
  /// mutation locale (ajout/suppression) et par le bouton « Réessayer »
  /// de [NubiaErrorWidget].
  Future<void> loadSection() async {
    setState(() => loading = true);
    await _fetchAndApply();
  }

  Future<void> _fetchAndApply() async {
    final result = await fetchSection();
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        error = failure.message;
        accessDenied = failure is ServerFailure && failure.statusCode == 403;
        loading = false;
      }),
      (value) => setState(() {
        data = value;
        error = null;
        accessDenied = false;
        loading = false;
      }),
    );
  }
}
