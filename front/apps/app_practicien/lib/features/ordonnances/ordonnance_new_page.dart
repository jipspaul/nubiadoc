import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'send_to_pharmacy_cubit.dart';
import 'widgets/prescription_template_picker.dart';
import 'widgets/send_to_pharmacy_card.dart';
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
            state is OrdonnancesSigningInProgress ||
            state is OrdonnancesApplyingTemplate) {
          final prescription = switch (state) {
            OrdonnancesCreated(:final prescription) => prescription,
            OrdonnancesSigningInProgress(:final prescription) => prescription,
            OrdonnancesApplyingTemplate(:final prescription) => prescription,
            _ => throw StateError('unreachable'),
          };
          return _DraftReview(
            prescription: prescription,
            signing: state is OrdonnancesSigningInProgress,
            applyingTemplate: state is OrdonnancesApplyingTemplate,
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
              NubiaButton(
                key: const Key('add_item_button'),
                label: 'Ajouter un médicament',
                variant: NubiaButtonVariant.secondary,
                icon: Icons.add,
                onPressed: widget.loading
                    ? null
                    : () => setState(() => _items.add(_ItemDraft())),
              ),
              const SizedBox(height: 24),
              NubiaButton(
                key: const Key('submit_ordonnance_button'),
                label: 'Créer l\'ordonnance',
                isLoading: widget.loading,
                onPressed: (!_formValid || widget.loading) ? null : _submit,
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
    return NubiaCard(
      key: Key('item_card_$index'),
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
    );
  }
}

// ---------------------------------------------------------------------------

/// Ordonnance créée (brouillon) : relecture des lignes + signature.
class _DraftReview extends StatelessWidget {
  const _DraftReview({
    required this.prescription,
    required this.signing,
    required this.applyingTemplate,
  });
  final Prescription prescription;
  final bool signing;
  final bool applyingTemplate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final busy = signing || applyingTemplate;

    return Column(
      key: const Key('ordonnance_draft_review'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: NubiaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${prescription.items.length} médicament(s)',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: cs.onSurface),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const StatusPill(
                      label: 'Brouillon',
                      variant: StatusPillVariant.info,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                NubiaButton(
                  key: const Key('use_template_button'),
                  label: 'Utiliser un modèle',
                  variant: NubiaButtonVariant.secondary,
                  icon: Icons.description_outlined,
                  isLoading: applyingTemplate,
                  onPressed: busy
                      ? null
                      : () async {
                          final bloc = context.read<OrdonnancesBloc>();
                          final template =
                              await PrescriptionTemplatePicker.show(context,
                                  loadTemplates: bloc.loadTemplates);
                          if (template != null) {
                            bloc.add(OrdonnancesApplyTemplateRequested(
                              prescriptionId: prescription.id,
                              templateId: template.id,
                            ));
                          }
                        },
                ),
                const SizedBox(height: 8),
                NubiaButton(
                  key: const Key('sign_ordonnance_button'),
                  label: 'Signer l\'ordonnance',
                  icon: Icons.draw_outlined,
                  isLoading: signing,
                  onPressed: busy
                      ? null
                      : () => context
                          .read<OrdonnancesBloc>()
                          .add(OrdonnancesSignRequested(prescription.id)),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: prescription.items.length,
            itemBuilder: (context, i) {
              final item = prescription.items[i];
              return ListRow(
                key: Key('draft_item_$i'),
                title: item.label,
                subtitle: '${item.posology} — ${item.duration}',
                leading: const Icon(Icons.medication_outlined, size: 22),
                trailing: Text(
                  item.quantity,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
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

  static Widget sendCard(Prescription prescription) => BlocProvider(
        create: (_) =>
            GetIt.instance<SendToPharmacyCubit>()..load(prescription.patientId),
        child: SendToPharmacyCard(prescription: prescription),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = theme.extension<NubiaTokens>()!;

    return Center(
      key: const Key('ordonnance_signed_confirmation'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: tokens.successBg,
                shape: BoxShape.circle,
              ),
              child:
                  Icon(Icons.check_rounded, size: 48, color: tokens.successFg),
            ),
            const SizedBox(height: 20),
            Text(
              'Ordonnance signée',
              style: theme.textTheme.titleLarge?.copyWith(color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              '${prescription.items.length} médicament(s) prescrits',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            sendCard(prescription),
            const SizedBox(height: 16),
            NubiaButton(
              key: const Key('back_to_ordonnances_button'),
              label: 'Retour aux ordonnances',
              variant: NubiaButtonVariant.secondary,
              onPressed: () => context
                  .go('/ordonnances?patientId=${prescription.patientId}'),
            ),
          ],
        ),
      ),
    );
  }
}
