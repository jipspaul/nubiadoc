import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' show ProNavDestination;
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Ouvre la recherche globale (#6311, même mécanique que
/// `app_secretariat/.../global_search_dialog.dart`, #5143/#5389/#5580) :
/// point d'entrée unique pour destinations de nav et patients. Actes et
/// ordonnances (cf. libellé maquette « Patient, acte, ordonnance… ») restent
/// hors périmètre pour l'instant et sont signalés comme tels plutôt que
/// silencieusement absents (même précédent que stock/commandes pharmacie
/// côté secrétariat, #5581).
void openGlobalSearchDialog(
  BuildContext context, {
  List<ProNavDestination> destinations = const [],
}) {
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
              _GlobalSearchBody(destinations: destinations),
            ],
          ),
        ),
      ),
    ),
  );
}

class _GlobalSearchResult {
  const _GlobalSearchResult({
    required this.id,
    required this.title,
    required this.subtitle,
  });

  final String id;
  final String title;
  final String subtitle;
}

enum _GlobalSearchStatus { idle, loading, loaded, error }

/// Corps du dialogue de recherche globale (#6311) : filtre localement les
/// destinations de nav sur leur libellé, et interroge
/// [ListCabinetPatientsUseCase] (recherche serveur, `q`) sur la même saisie.
/// Se déclenche à la saisie (debounce 300ms) et à la validation
/// (`onSubmitted`, immédiate — annule le debounce en attente pour éviter une
/// recherche redondante). Navigable au clavier (flèches ↑/↓ + Entrée) sans
/// souris, cf. [_handleKey]/[_activateHighlighted].
class _GlobalSearchBody extends StatefulWidget {
  const _GlobalSearchBody({required this.destinations});

  final List<ProNavDestination> destinations;

  @override
  State<_GlobalSearchBody> createState() => _GlobalSearchBodyState();
}

class _GlobalSearchBodyState extends State<_GlobalSearchBody> {
  _GlobalSearchStatus _status = _GlobalSearchStatus.idle;
  List<_GlobalSearchResult> _results = const [];
  String _query = '';
  String _liveQuery = '';
  int _highlightedIndex = 0;
  Timer? _debounce;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _handleKey);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  /// Destinations dont le libellé matche [_liveQuery] — filtre local,
  /// synchrone (pas de debounce nécessaire, contrairement à la recherche
  /// patients serveur ci-dessous). Champ vide : toutes les destinations,
  /// pour permettre de naviguer la liste complète aux flèches sans avoir à
  /// taper.
  List<ProNavDestination> get _destinationMatches {
    final q = _liveQuery.trim().toLowerCase();
    if (q.isEmpty) return widget.destinations;
    return widget.destinations
        .where((d) => d.label.toLowerCase().contains(q))
        .toList();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final total = _destinationMatches.length + _results.length;
    if (total == 0) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _highlightedIndex = (_highlightedIndex + 1) % total);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _highlightedIndex = (_highlightedIndex - 1 + total) % total);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _openDestination(ProNavDestination destination) {
    Navigator.of(context).pop();
    context.go(destination.route);
  }

  void _activateHighlighted() {
    final destinations = _destinationMatches;
    if (_highlightedIndex < destinations.length) {
      _openDestination(destinations[_highlightedIndex]);
      return;
    }
    final resultIndex = _highlightedIndex - destinations.length;
    if (resultIndex >= 0 && resultIndex < _results.length) {
      _openResult(_results[resultIndex]);
    }
  }

  void _onChanged(String query) {
    setState(() {
      _liveQuery = query;
      _highlightedIndex = 0;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(query));
  }

  void _onSubmitted(String query) {
    final total = _destinationMatches.length + _results.length;
    if (total > 0 && _highlightedIndex < total) {
      _activateHighlighted();
      return;
    }
    _debounce?.cancel();
    _search(query);
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _status = _GlobalSearchStatus.idle;
        _results = const [];
        _highlightedIndex = 0;
      });
      return;
    }
    setState(() {
      _status = _GlobalSearchStatus.loading;
      _query = trimmed;
    });

    final patientsEither =
        await GetIt.instance<ListCabinetPatientsUseCase>()(q: trimmed);

    if (!mounted) return;

    if (patientsEither.isLeft()) {
      setState(() => _status = _GlobalSearchStatus.error);
      return;
    }

    final results = patientsEither.fold(
      (_) => const <_GlobalSearchResult>[],
      (patients) => patients
          .map(
            (p) => _GlobalSearchResult(
              id: p.id,
              title: '${p.firstName} ${p.lastName}',
              subtitle: 'Patient',
            ),
          )
          .toList(),
    );

    setState(() {
      _status = _GlobalSearchStatus.loaded;
      _results = results;
      _highlightedIndex = 0;
    });
  }

  void _openResult(_GlobalSearchResult result) {
    Navigator.of(context).pop();
    context.go('/patients/${result.id}');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final destinations = _destinationMatches;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NubiaSearchBar(
          focusNode: _focusNode,
          hint: 'Patient, acte, ordonnance…',
          onChanged: _onChanged,
          onSubmitted: _onSubmitted,
        ),
        const SizedBox(height: 4),
        Text(
          'Recherche patients. Actes et ordonnances : à venir.',
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        if (destinations.isNotEmpty) _buildDestinations(context, destinations),
        _buildResults(context, highlightBase: destinations.length),
      ],
    );
  }

  Widget _buildDestinations(
    BuildContext context,
    List<ProNavDestination> destinations,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: ListView.builder(
        key: const Key('global_search_destinations'),
        shrinkWrap: true,
        itemCount: destinations.length,
        itemBuilder: (context, index) {
          final destination = destinations[index];
          return ListTile(
            leading: Icon(destination.icon),
            title: Text(destination.label),
            selected: index == _highlightedIndex,
            onTap: () => _openDestination(destination),
          );
        },
      ),
    );
  }

  Widget _buildResults(BuildContext context, {required int highlightBase}) {
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
                selected: highlightBase + index == _highlightedIndex,
                leading: const Icon(Icons.person_outline),
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
