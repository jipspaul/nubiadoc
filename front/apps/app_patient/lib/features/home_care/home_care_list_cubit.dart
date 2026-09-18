import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';

import 'home_care_models.dart';

sealed class HomeCareListState extends Equatable {
  const HomeCareListState();

  @override
  List<Object?> get props => [];
}

final class HomeCareListLoading extends HomeCareListState {
  const HomeCareListLoading();
}

final class HomeCareListLoaded extends HomeCareListState {
  const HomeCareListLoaded(this.requests, {this.skippedCount = 0});

  /// Lignes décodées avec succès (récentes d'abord, ordre de l'API).
  final List<VisitRequest> requests;

  /// Lignes renvoyées par l'API mais indécodables (élément non-objet, `id`
  /// manquant…), écartées pour ne pas bloquer l'affichage des autres —
  /// #6961 / #6861. `> 0` ⇒ succès partiel signalé à l'écran.
  final int skippedCount;

  @override
  List<Object?> get props => [requests, skippedCount];
}

final class HomeCareListError extends HomeCareListState {
  const HomeCareListError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Résultat du décodage ligne à ligne d'une réponse liste.
typedef DecodedVisitRequests = ({List<VisitRequest> requests, int skipped});

/// Décode chaque élément **indépendamment** : une ligne corrompue est
/// comptée dans `skipped` au lieu de faire échouer toute la liste
/// (#6961 / #6861 — 1 ligne sur 50 rendait l'écran inutilisable).
DecodedVisitRequests decodeVisitRequests(List<dynamic> raw) {
  final requests = <VisitRequest>[];
  var skipped = 0;
  for (final e in raw) {
    if (e is! Map) {
      skipped++;
      continue;
    }
    try {
      requests.add(
        VisitRequest.fromJson(e.map((k, v) => MapEntry('$k', v))),
      );
    } on FormatException {
      // `id` manquant/invalide — ligne inexploitable.
      skipped++;
    } on TypeError {
      // Filet de sécurité : un cast futur non gardé dans `fromJson` ne doit
      // jamais redevenir un spinner infini pour toute la liste.
      skipped++;
    }
  }
  return (requests: requests, skipped: skipped);
}

/// Liste des demandes de visite du patient (`GET /v1/account/visit-requests`,
/// récentes d'abord — cf. `list_account_visit_requests`).
class HomeCareListCubit extends Cubit<HomeCareListState>
    with SafeEmitMixin<HomeCareListState> {
  HomeCareListCubit(this._api) : super(const HomeCareListLoading());

  final ApiClient _api;

  /// Émet **toujours** un état final ([HomeCareListLoaded] ou
  /// [HomeCareListError]) : une exception de décodage ou de transport qui
  /// n'est pas une [DioException] ne doit jamais laisser l'écran sur
  /// [HomeCareListLoading] (spinner infini, #6961 / #6861).
  Future<void> load() async {
    safeEmit(const HomeCareListLoading());
    try {
      final res = await _api.dio.get<List<dynamic>>('/account/visit-requests');
      final decoded = decodeVisitRequests(res.data ?? const []);
      safeEmit(HomeCareListLoaded(
        decoded.requests,
        skippedCount: decoded.skipped,
      ));
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      safeEmit(HomeCareListError('Erreur réseau (${code ?? 'hors ligne'}).'));
    } catch (_) {
      // Réponse d'une forme inattendue (ex. objet au lieu de liste) : l'état
      // d'erreur câblé (« Réessayer ») vaut mieux qu'un spinner sans issue.
      safeEmit(const HomeCareListError('Réponse inattendue du serveur.'));
    }
  }
}
