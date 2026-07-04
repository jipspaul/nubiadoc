import 'package:nubia_data/nubia_data.dart';

import 'ccam_picker.dart';

/// Implémentation réelle de [GetActsUseCase] : interroge le référentiel CCAM
/// via GET /v1/ccam/acts (#3226), en remplacement du stub local.
class ApiGetActsUseCase implements GetActsUseCase {
  final ClinicalSessionApi _api;
  const ApiGetActsUseCase(this._api);

  @override
  Future<List<CcamAct>> search(String prefix) async {
    final acts = await _api.searchCcamActs(prefix);
    return acts.map((a) => CcamAct(code: a.code, label: a.label)).toList();
  }
}
