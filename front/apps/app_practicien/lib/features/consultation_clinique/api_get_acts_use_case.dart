import 'package:nubia_data/nubia_data.dart';

import 'ccam_picker.dart';

/// Implémentation réelle de [GetActsUseCase] : interroge le référentiel CCAM
/// via GET /v1/ccam/acts (#3226), en remplacement du stub local.
class ApiGetActsUseCase implements GetActsUseCase {
  final ClinicalSessionApi _api;
  const ApiGetActsUseCase(this._api);

  @override
  Future<List<CcamAct>> search(String prefix, {String? tooth}) async {
    final acts = await _api.searchCcamActs(prefix, tooth: tooth);
    return acts
        .map((a) =>
            CcamAct(code: a.code, label: a.label, tarifCents: a.tarifCents))
        .toList();
  }
}

/// Implémentation réelle de [FavoriteActsUseCase] (#4112/#4113).
class ApiFavoriteActsUseCase implements FavoriteActsUseCase {
  final ClinicalSessionApi _api;
  const ApiFavoriteActsUseCase(this._api);

  @override
  Future<List<CcamAct>> list() async {
    final acts = await _api.listFavoriteActs();
    return acts
        .map((a) =>
            CcamAct(code: a.code, label: a.label, tarifCents: a.tarifCents))
        .toList();
  }

  @override
  Future<void> add(String ccamCode) => _api.addFavoriteAct(ccamCode);

  @override
  Future<void> remove(String ccamCode) => _api.removeFavoriteAct(ccamCode);
}
