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
    return BlocProvider(
      create: (_) => GetIt.instance<OrdonnancesBloc>(),
      child: OrdonnancesBody(patientId: patientId),
    );
  }
}

// ---------------------------------------------------------------------------

/// Corps de la page ordonnances, consommable dans ProShell bodyBuilder.
class OrdonnancesBody extends StatelessWidget {
  const OrdonnancesBody({super.key, this.patientId});
  final String? patientId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OrdonnancesBloc, OrdonnancesState>(
      builder: (context, state) {
        if (state is OrdonnancesLoading) {
          return const _LoadingView(key: Key('ordonnances_loading'));
        }
        if (state is OrdonnancesLoaded && state.ordonnances.isEmpty) {
          return NubiaEmptyState(
            key: const Key('ordonnances_empty'),
            icon: Icons.description_outlined,
            title: 'Aucune ordonnance',
            subtitle: 'Crée la première',
            action: NubiaButton(
              key: const Key('create_ordonnance_button'),
              label: 'Créer une ordonnance',
              icon: Icons.add,
              onPressed: () => context.push('/ordonnances/new'),
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
        if (state is OrdonnancesSigningInProgress) {
          return _CreatedView(prescription: state.prescription, signing: true);
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

class _LoadingView extends StatelessWidget {
  const _LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: const [
        NubiaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NubiaSkeletonLoader(height: 16, width: 160),
              SizedBox(height: 12),
              NubiaSkeletonLoader(height: 12, width: 220),
              SizedBox(height: 8),
              NubiaSkeletonLoader(height: 12, width: 180),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _InitialView extends StatelessWidget {
  const _InitialView({this.patientId});
  final String? patientId;

  @override
  Widget build(BuildContext context) {
    return NubiaEmptyState(
      key: const Key('ordonnances_initial'),
      icon: Icons.medication_outlined,
      title: 'Aucune ordonnance en cours',
      subtitle: patientId == null
          ? 'Ouvrez une fiche patient pour créer une ordonnance.'
          : null,
      action: patientId == null
          ? null
          : NubiaButton(
              key: const Key('create_ordonnance_button'),
              label: 'Nouvelle ordonnance',
              icon: Icons.add,
              onPressed: () =>
                  context.push('/ordonnances/new?patientId=$patientId'),
            ),
    );
  }
}

// ---------------------------------------------------------------------------

class _CreatedView extends StatefulWidget {
  const _CreatedView({required this.prescription, this.signing = false});
  final Prescription prescription;
  final bool signing;

  @override
  State<_CreatedView> createState() => _CreatedViewState();
}

class _CreatedViewState extends State<_CreatedView> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
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
          child: NubiaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.prescription.items.length} médicament(s)',
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
                  key: const Key('sign_ordonnance_button'),
                  label: 'Signer l\'ordonnance',
                  icon: Icons.draw_outlined,
                  isLoading: widget.signing,
                  onPressed: widget.signing
                      ? null
                      : () => context.read<OrdonnancesBloc>().add(
                          OrdonnancesSignRequested(widget.prescription.id)),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: NubiaSearchBar(
            key: const Key('medication_search'),
            hint: 'Filtrer par médicament',
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: const Key('ordonnances_items_list'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
    final theme = Theme.of(context);
    return ListRow(
      key: Key('item_$index'),
      title: item.label,
      subtitle: '${item.posology} — ${item.duration}',
      leading: const Icon(Icons.medication_outlined, size: 22),
      trailing: Text(
        item.quantity,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = theme.extension<NubiaTokens>()!;

    return Center(
      key: const Key('ordonnances_signed'),
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
            child: Icon(Icons.check_rounded, size: 48, color: tokens.successFg),
          ),
          const SizedBox(height: 20),
          Text(
            'Ordonnance signée',
            style: theme.textTheme.titleLarge?.copyWith(color: cs.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            '${prescription.items.length} médicament(s)',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
