import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Ouvre la recherche globale (#5389/#5580) — point d'entrée unique pour
/// patient/devis. Le dispatch interroge patients (recherche serveur) et
/// devis (filtre client, cf. [_GlobalSearchBody]) sur le même terme ;
/// stock/commandes pharmacie restent hors périmètre (#5581) et sont
/// signalés comme tels plutôt que silencieusement absents.
void openGlobalSearchDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      key: const Key('global_search_dialog'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recherche globale',
                style: Theme.of(dialogContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              const _GlobalSearchBody(),
            ],
          ),
        ),
      ),
    ),
  );
}

enum _GlobalSearchResultType { patient, quote }

class _GlobalSearchResult {
  const _GlobalSearchResult({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
  });

  final _GlobalSearchResultType type;
  final String id;
  final String title;
  final String subtitle;
}

enum _GlobalSearchStatus { idle, loading, loaded, error }

/// Corps du dialogue de recherche globale (#5389/#5581) : interroge
/// [ListCabinetPatientsUseCase] (recherche serveur, `q`) et
/// [ListCabinetQuotesUseCase] (filtré côté client sur le nom du patient — le
/// endpoint ne supporte pas encore de paramètre `q`) sur la même saisie, puis
/// fusionne les résultats. Se déclenche à la saisie (debounce 300ms, #5579)
/// et à la validation (`onSubmitted`, immédiate — annule le debounce en
/// attente pour éviter une recherche redondante).
class _GlobalSearchBody extends StatefulWidget {
  const _GlobalSearchBody();

  @override
  State<_GlobalSearchBody> createState() => _GlobalSearchBodyState();
}

class _GlobalSearchBodyState extends State<_GlobalSearchBody> {
  _GlobalSearchStatus _status = _GlobalSearchStatus.idle;
  List<_GlobalSearchResult> _results = const [];
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(query));
  }

  void _onSubmitted(String query) {
    _debounce?.cancel();
    _search(query);
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _status = _GlobalSearchStatus.idle;
        _results = const [];
      });
      return;
    }
    setState(() {
      _status = _GlobalSearchStatus.loading;
      _query = trimmed;
    });

    final patientsEither =
        await GetIt.instance<ListCabinetPatientsUseCase>()(q: trimmed);
    final quotesEither = await GetIt.instance<ListCabinetQuotesUseCase>()();

    if (!mounted) return;

    if (patientsEither.isLeft() && quotesEither.isLeft()) {
      setState(() => _status = _GlobalSearchStatus.error);
      return;
    }

    final lowerQuery = trimmed.toLowerCase();
    final results = <_GlobalSearchResult>[
      ...patientsEither.fold(
        (_) => const <_GlobalSearchResult>[],
        (patients) => patients.map(
          (p) => _GlobalSearchResult(
            type: _GlobalSearchResultType.patient,
            id: p.id,
            title: '${p.firstName} ${p.lastName}',
            subtitle: 'Patient',
          ),
        ),
      ),
      ...quotesEither.fold(
        (_) => const <_GlobalSearchResult>[],
        (quotes) => quotes
            .where((q) => q.patientName.toLowerCase().contains(lowerQuery))
            .map(
              (q) => _GlobalSearchResult(
                type: _GlobalSearchResultType.quote,
                id: q.id,
                title: q.patientName,
                subtitle: 'Devis',
              ),
            ),
      ),
    ];

    setState(() {
      _status = _GlobalSearchStatus.loaded;
      _results = results;
    });
  }

  void _openResult(_GlobalSearchResult result) {
    Navigator.of(context).pop();
    switch (result.type) {
      case _GlobalSearchResultType.patient:
        context.push('/patients', extra: result.id);
      case _GlobalSearchResultType.quote:
        context.push('/devis/${result.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NubiaSearchBar(
          hint: 'Patient, devis, commande…',
          onChanged: _onChanged,
          onSubmitted: _onSubmitted,
        ),
        const SizedBox(height: 4),
        Text(
          'Recherche patients et devis. Stock/commandes pharmacie : à venir.',
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        _buildResults(context),
      ],
    );
  }

  Widget _buildResults(BuildContext context) {
    switch (_status) {
      case _GlobalSearchStatus.idle:
        return const SizedBox.shrink();
      case _GlobalSearchStatus.loading:
        return const Padding(
          key: Key('global_search_loading'),
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator()),
        );
      case _GlobalSearchStatus.error:
        return const Padding(
          key: Key('global_search_error'),
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Recherche indisponible pour le moment.'),
        );
      case _GlobalSearchStatus.loaded:
        if (_results.isEmpty) {
          return Padding(
            key: const Key('global_search_empty'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Aucun résultat pour « $_query ».'),
          );
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: ListView.builder(
            key: const Key('global_search_results'),
            shrinkWrap: true,
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final result = _results[index];
              return ListTile(
                leading: Icon(
                  result.type == _GlobalSearchResultType.patient
                      ? Icons.person_outline
                      : Icons.description_outlined,
                ),
                title: Text(result.title),
                subtitle: Text(result.subtitle),
                onTap: () => _openResult(result),
              );
            },
          ),
        );
    }
  }
}
