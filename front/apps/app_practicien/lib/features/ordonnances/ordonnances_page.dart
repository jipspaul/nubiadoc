import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'ordonnances_bloc.dart';
import 'ordonnances_event.dart';
import 'ordonnances_state.dart';

/// Ordonnances — gated par [ProConfig.includeClinical] au niveau du router.
/// Permet de créer et signer une ordonnance pour un patient donné.
/// [patientId] est passé en query param `?patientId=`.
class OrdonnancesPage extends StatelessWidget {
  final String? patientId;

  const OrdonnancesPage({super.key, this.patientId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: GetIt.instance<OrdonnancesBloc>(),
      child: _OrdonnancesBody(patientId: patientId),
    );
  }
}

// ---------------------------------------------------------------------------

class _OrdonnancesBody extends StatelessWidget {
  const _OrdonnancesBody({this.patientId});
  final String? patientId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OrdonnancesBloc, OrdonnancesState>(
      builder: (context, state) {
        if (state is OrdonnancesLoading) {
          return const Center(
            key: Key('ordonnances_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is OrdonnancesLoaded && state.ordonnances.isEmpty) {
          return NubiaEmptyState(
            key: const Key('ordonnances_empty'),
            icon: Icons.description,
            title: 'Aucune ordonnance',
            subtitle: 'Crée la première',
            action: ElevatedButton(
              onPressed: () => context.push('/ordonnances/new'),
              child: const Text('Créer une ordonnance'),
            ),
          );
        }
        if (state is OrdonnancesError) {
          return NubiaErrorWidget(
            key: const Key('ordonnances_error'),
            message: state.message,
          );
        }
        if (state is OrdonnancesCreated) {
          return _CreatedView(prescription: state.prescription);
        }
        if (state is OrdonnancesSigned) {
          return _SignedView(prescription: state.prescription);
        }
        // OrdonnancesInitial
        return _InitialView(patientId: patientId);
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _InitialView extends StatelessWidget {
  const _InitialView({this.patientId});
  final String? patientId;

  static const _sampleItems = [
    PrescriptionItem(
      label: 'Amoxicilline 500 mg',
      posology: '1 comprimé 3x/jour',
      duration: '7 jours',
      quantity: '21',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('ordonnances_initial'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.medication_outlined, size: 64),
          const SizedBox(height: 16),
          const Text('Aucune ordonnance en cours'),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('create_ordonnance_button'),
            onPressed: patientId == null
                ? null
                : () => context.read<OrdonnancesBloc>().add(
                      OrdonnancesCreateRequested(
                        patientId: patientId!,
                        items: _sampleItems,
                      ),
                    ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nouvelle ordonnance'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _CreatedView extends StatefulWidget {
  const _CreatedView({required this.prescription});
  final Prescription prescription;

  @override
  State<_CreatedView> createState() => _CreatedViewState();
}

class _CreatedViewState extends State<_CreatedView> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.prescription.items
        : widget.prescription.items
            .where((item) =>
                item.label.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.prescription.items.length} médicament(s)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                key: const Key('sign_ordonnance_button'),
                onPressed: () => context
                    .read<OrdonnancesBloc>()
                    .add(OrdonnancesSignRequested(widget.prescription.id)),
                icon: const Icon(Icons.draw_outlined, size: 18),
                label: const Text('Signer'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            key: const Key('medication_search'),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Filtrer par médicament',
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            key: const Key('ordonnances_items_list'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: filtered.length,
            itemBuilder: (context, i) => _ItemTile(item: filtered[i], index: i),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.index});
  final PrescriptionItem item;
  final int index;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('item_$index'),
      title: Text(item.label),
      subtitle: Text('${item.posology} — ${item.duration}'),
      trailing: Text(
        item.quantity,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SignedView extends StatelessWidget {
  const _SignedView({required this.prescription});
  final Prescription prescription;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('ordonnances_signed'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
          const SizedBox(height: 16),
          const Text('Ordonnance signée'),
          const SizedBox(height: 8),
          Text(
            '${prescription.items.length} médicament(s)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
