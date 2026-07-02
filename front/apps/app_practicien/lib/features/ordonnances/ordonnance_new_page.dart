import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'ordonnances_bloc.dart';
import 'ordonnances_event.dart';
import 'ordonnances_state.dart';

/// Composition d'une nouvelle ordonnance (`/ordonnances/new?patientId=`).
/// Gated par [ProConfig.includeClinical] au niveau du router (route parente).
class OrdonnanceNewPage extends StatelessWidget {
  final String? patientId;

  const OrdonnanceNewPage({super.key, this.patientId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<OrdonnancesBloc>(),
      child: OrdonnanceNewBody(patientId: patientId),
    );
  }
}

// ---------------------------------------------------------------------------

class OrdonnanceNewBody extends StatelessWidget {
  const OrdonnanceNewBody({super.key, this.patientId});
  final String? patientId;

  @override
  Widget build(BuildContext context) {
    final pid = patientId;
    if (pid == null || pid.isEmpty) {
      return const NubiaEmptyState(
        key: Key('ordonnances_new'),
        icon: Icons.medication_outlined,
        title: 'Nouvelle ordonnance',
        subtitle: 'Ouvrez une fiche patient pour prescrire.',
      );
    }
    return BlocConsumer<OrdonnancesBloc, OrdonnancesState>(
      listener: (context, state) {
        if (state is OrdonnancesError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        if (state is OrdonnancesSigned) {
          return _SignedConfirmation(prescription: state.prescription);
        }
        if (state is OrdonnancesCreated ||
            state is OrdonnancesSigningInProgress) {
          final prescription = state is OrdonnancesCreated
              ? state.prescription
              : (state as OrdonnancesSigningInProgress).prescription;
          return _DraftReview(
            prescription: prescription,
            signing: state is OrdonnancesSigningInProgress,
          );
        }
        // Initial, Loading, Error : le formulaire reste monté pour ne pas
        // perdre la saisie (l'erreur est surfacée en snackbar).
        return _PrescriptionForm(
          patientId: pid,
          loading: state is OrdonnancesLoading,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

/// Une ligne de médicament en cours de saisie (controllers par champ).
class _ItemDraft {
  final label = TextEditingController();
  final posology = TextEditingController();
  final duration = TextEditingController();
  final quantity = TextEditingController();

  bool get isValid =>
      label.text.trim().isNotEmpty &&
      posology.text.trim().isNotEmpty &&
      duration.text.trim().isNotEmpty &&
      quantity.text.trim().isNotEmpty;

  PrescriptionItem toItem() => PrescriptionItem(
        label: label.text.trim(),
        posology: posology.text.trim(),
        duration: duration.text.trim(),
        quantity: quantity.text.trim(),
      );

  void dispose() {
    label.dispose();
    posology.dispose();
    duration.dispose();
    quantity.dispose();
  }
}

class _PrescriptionForm extends StatefulWidget {
  const _PrescriptionForm({required this.patientId, required this.loading});
  final String patientId;
  final bool loading;

  @override
  State<_PrescriptionForm> createState() => _PrescriptionFormState();
}

class _PrescriptionFormState extends State<_PrescriptionForm> {
  final List<_ItemDraft> _items = [_ItemDraft()];

  bool get _formValid => _items.isNotEmpty && _items.every((i) => i.isValid);

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _submit() {
    context.read<OrdonnancesBloc>().add(
          OrdonnancesCreateRequested(
            patientId: widget.patientId,
            items: _items.map((i) => i.toItem()).toList(),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('ordonnance_form'),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Médicaments à prescrire',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              for (var i = 0; i < _items.length; i++) ...[
                _ItemCard(
                  index: i,
                  draft: _items[i],
                  onChanged: _refresh,
                  onRemove: _items.length == 1
                      ? null
                      : () => setState(() => _items.removeAt(i).dispose()),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                key: const Key('add_item_button'),
                onPressed: widget.loading
                    ? null
                    : () => setState(() => _items.add(_ItemDraft())),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Ajouter un médicament'),
              ),
              const SizedBox(height: 24),
              NubiaButton(
                key: const Key('submit_ordonnance_button'),
                label: 'Créer l\'ordonnance',
                isLoading: widget.loading,
                onPressed:
                    (!_formValid || widget.loading) ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.index,
    required this.draft,
    required this.onChanged,
    this.onRemove,
  });

  final int index;
  final _ItemDraft draft;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('item_card_$index'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Médicament ${index + 1}',
                      style: Theme.of(context).textTheme.labelLarge),
                ),
                if (onRemove != null)
                  IconButton(
                    key: Key('remove_item_$index'),
                    tooltip: 'Retirer',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            NubiaTextField(
              key: Key('item_${index}_label'),
              controller: draft.label,
              label: 'Médicament (DCI)',
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 12),
            NubiaTextField(
              key: Key('item_${index}_posology'),
              controller: draft.posology,
              label: 'Posologie',
              hint: 'ex. 1 comprimé matin et soir',
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: NubiaTextField(
                    key: Key('item_${index}_duration'),
                    controller: draft.duration,
                    label: 'Durée',
                    hint: 'ex. 7 jours',
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: NubiaTextField(
                    key: Key('item_${index}_quantity'),
                    controller: draft.quantity,
                    label: 'Quantité',
                    hint: 'ex. 1 boîte',
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Ordonnance créée (brouillon) : relecture des lignes + signature.
class _DraftReview extends StatelessWidget {
  const _DraftReview({required this.prescription, required this.signing});
  final Prescription prescription;
  final bool signing;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('ordonnance_draft_review'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Brouillon — ${prescription.items.length} médicament(s)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                key: const Key('sign_ordonnance_button'),
                onPressed: signing
                    ? null
                    : () => context
                        .read<OrdonnancesBloc>()
                        .add(OrdonnancesSignRequested(prescription.id)),
                icon: const Icon(Icons.draw_outlined, size: 18),
                label: const Text('Signer'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: prescription.items.length,
            itemBuilder: (context, i) {
              final item = prescription.items[i];
              return ListTile(
                key: Key('draft_item_$i'),
                title: Text(item.label),
                subtitle: Text('${item.posology} — ${item.duration}'),
                trailing: Text(item.quantity,
                    style: Theme.of(context).textTheme.bodySmall),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SignedConfirmation extends StatelessWidget {
  const _SignedConfirmation({required this.prescription});
  final Prescription prescription;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('ordonnance_signed_confirmation'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
          const SizedBox(height: 16),
          const Text('Ordonnance signée'),
          const SizedBox(height: 8),
          Text(
            '${prescription.items.length} médicament(s) prescrits',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            key: const Key('back_to_ordonnances_button'),
            onPressed: () => context
                .go('/ordonnances?patientId=${prescription.patientId}'),
            child: const Text('Retour aux ordonnances'),
          ),
        ],
      ),
    );
  }
}
