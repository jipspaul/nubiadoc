import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'referring_doctor_search_cubit.dart';

/// Recherche d'un praticien Nubia à déclarer comme médecin traitant.
///
/// Retourne le [ProviderResult] sélectionné via `context.pop(provider)`.
class ReferringDoctorSearchPage extends StatelessWidget {
  const ReferringDoctorSearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ReferringDoctorSearchCubit>(
      create: (_) => GetIt.instance<ReferringDoctorSearchCubit>()..search(''),
      child: const ReferringDoctorSearchBody(),
    );
  }
}

/// Corps de l'écran — public pour les tests widget.
class ReferringDoctorSearchBody extends StatefulWidget {
  const ReferringDoctorSearchBody({super.key});

  @override
  State<ReferringDoctorSearchBody> createState() =>
      _ReferringDoctorSearchBodyState();
}

class _ReferringDoctorSearchBodyState
    extends State<ReferringDoctorSearchBody> {
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
        context.read<ReferringDoctorSearchCubit>().search(query);
      }
    });
  }

  Future<void> _select(ProviderResult provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Déclarer ${provider.displayName} comme médecin '
            'traitant ?'),
        content: const Text(
            'Il sera identifié comme votre médecin traitant sur Nubia.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            key: const Key('confirm_declare_provider'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Déclarer'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context.pop(provider);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rechercher un praticien')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: NubiaSearchBar(
              hint: 'Nom du médecin ou spécialité',
              onChanged: _onQueryChanged,
            ),
          ),
          Expanded(
            child: BlocBuilder<ReferringDoctorSearchCubit,
                ReferringDoctorSearchState>(
              builder: (context, state) {
                switch (state) {
                  case ReferringDoctorSearchLoading():
                    return const Center(child: CircularProgressIndicator());
                  case ReferringDoctorSearchError(:final message):
                    return NubiaErrorWidget(message: message);
                  case ReferringDoctorSearchResults(:final providers):
                    if (providers.isEmpty) {
                      return const NubiaEmptyState(
                        icon: Icons.search_off,
                        title: 'Aucun résultat',
                        subtitle: 'Essayez un autre nom, ou saisissez ses '
                            'coordonnées manuellement.',
                      );
                    }
                    return ListView.builder(
                      itemCount: providers.length,
                      itemBuilder: (context, index) {
                        final provider = providers[index];
                        return ListRow(
                          key: Key('provider_result_${provider.id}'),
                          title: provider.displayName,
                          subtitle: [
                            provider.specialty,
                            if (provider.address != null) provider.address!,
                          ].join(' · '),
                          onTap: () => _select(provider),
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
