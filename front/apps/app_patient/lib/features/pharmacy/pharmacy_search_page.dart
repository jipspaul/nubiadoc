import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'pharmacy_search_cubit.dart';

/// Recherche d'une pharmacie dans l'annuaire public.
///
/// Retourne la [Pharmacy] sélectionnée via `context.pop(pharmacy)` quand
/// [selectionMode] est vrai ; sinon déclare directement la pharmacie.
class PharmacySearchPage extends StatelessWidget {
  const PharmacySearchPage({super.key, this.selectionMode = false});

  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PharmacySearchCubit>(
      create: (_) => GetIt.instance<PharmacySearchCubit>(),
      child: PharmacySearchBody(selectionMode: selectionMode),
    );
  }
}

/// Corps de l'écran — public pour les tests widget.
class PharmacySearchBody extends StatefulWidget {
  const PharmacySearchBody({super.key, this.selectionMode = false});

  final bool selectionMode;

  @override
  State<PharmacySearchBody> createState() => _PharmacySearchBodyState();
}

class _PharmacySearchBodyState extends State<PharmacySearchBody> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        context.read<PharmacySearchCubit>().search(query);
      }
    });
  }

  Future<void> _select(Pharmacy pharmacy) async {
    if (widget.selectionMode) {
      context.pop(pharmacy);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Déclarer ${pharmacy.name} ?'),
        content: const Text(
            'Vos ordonnances pourront lui être transmises en un geste.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            key: const Key('confirm_declare'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Déclarer'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context.pop(pharmacy);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trouver une pharmacie')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: NubiaSearchBar(
              hint: 'Nom de la pharmacie ou ville',
              onChanged: _onQueryChanged,
            ),
          ),
          Expanded(
            child: BlocBuilder<PharmacySearchCubit, PharmacySearchState>(
              builder: (context, state) {
                switch (state) {
                  case PharmacySearchIdle():
                    return const NubiaEmptyState(
                      icon: Icons.search,
                      title: 'Recherchez votre pharmacie',
                      subtitle:
                          'Saisissez son nom pour la trouver dans l\'annuaire.',
                    );
                  case PharmacySearchLoading():
                    return const Center(child: CircularProgressIndicator());
                  case PharmacySearchError(:final message):
                    return NubiaErrorWidget(message: message);
                  case PharmacySearchResults(:final pharmacies):
                    if (pharmacies.isEmpty) {
                      return const NubiaEmptyState(
                        icon: Icons.search_off,
                        title: 'Aucun résultat',
                        subtitle: 'Essayez un autre nom.',
                      );
                    }
                    return ListView.builder(
                      itemCount: pharmacies.length,
                      itemBuilder: (context, index) {
                        final pharmacy = pharmacies[index];
                        return ListRow(
                          key: Key('pharmacy_result_${pharmacy.id}'),
                          title: pharmacy.name,
                          subtitle: [
                            if (pharmacy.address != null) pharmacy.address!,
                            if (pharmacy.distanceKm != null)
                              'à ${pharmacy.distanceKm!.toStringAsFixed(1)} km',
                          ].join(' · '),
                          onTap: () => _select(pharmacy),
                        );
                      },
                    );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
