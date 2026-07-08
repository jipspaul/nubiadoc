import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Bottom sheet de choix d'une pharmacie (annuaire public, recherche par nom).
/// Retourne la [Pharmacy] sélectionnée via `Navigator.pop`.
Future<Pharmacy?> showPharmacyPickerSheet(BuildContext context) {
  return showModalBottomSheet<Pharmacy>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const PharmacyPickerSheet(),
  );
}

class PharmacyPickerSheet extends StatefulWidget {
  const PharmacyPickerSheet({super.key});

  @override
  State<PharmacyPickerSheet> createState() => _PharmacyPickerSheetState();
}

class _PharmacyPickerSheetState extends State<PharmacyPickerSheet> {
  final _search = GetIt.instance<SearchPharmaciesUseCase>();
  Timer? _debounce;
  List<Pharmacy> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted || query.trim().isEmpty) return;
      setState(() {
        _loading = true;
        _error = null;
      });
      final result = await _search(query: query.trim());
      if (!mounted) return;
      result.fold(
        (failure) => setState(() {
          _loading = false;
          _error = failure.message;
        }),
        (pharmacies) => setState(() {
          _loading = false;
          _results = pharmacies;
        }),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: 480,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: NubiaSearchBar(
                  hint: 'Nom de la pharmacie ou ville',
                  onChanged: _onQueryChanged,
                ),
              ),
              if (_loading)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Expanded(child: NubiaErrorWidget(message: _error!))
              else if (_results.isEmpty)
                const Expanded(
                  child: NubiaEmptyState(
                    icon: Icons.search,
                    title: 'Recherchez une pharmacie',
                    subtitle: 'Par nom ou par ville.',
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final pharmacy = _results[index];
                      return ListRow(
                        key: Key('picker_pharmacy_${pharmacy.id}'),
                        title: pharmacy.name,
                        subtitle: [
                          if (pharmacy.address != null) pharmacy.address!,
                          if (pharmacy.distanceKm != null)
                            'à ${pharmacy.distanceKm!.toStringAsFixed(1)} km',
                        ].join(' · '),
                        onTap: () => Navigator.of(context).pop(pharmacy),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
