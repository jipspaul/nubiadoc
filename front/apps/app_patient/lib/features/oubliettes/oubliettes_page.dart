import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'oubliettes_bloc.dart';

class OubliettesPage extends StatelessWidget {
  const OubliettesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<OubliettesBloc, OubliettesState>(
      listenWhen: (previous, current) =>
          current is OubliettesDocumentReady ||
          current is OubliettesDocumentError,
      listener: (context, state) {
        if (state is OubliettesDocumentReady) {
          openDocumentUrl(state.url).then((opened) {
            if (!opened && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Impossible d\'ouvrir ce document.'),
                ),
              );
            }
          });
          context.read<OubliettesBloc>().add(const OubliettesLoadRequested());
        }
        if (state is OubliettesDocumentError) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.message)));
          context.read<OubliettesBloc>().add(const OubliettesLoadRequested());
        }
      },
      child: BlocBuilder<OubliettesBloc, OubliettesState>(
        buildWhen: (previous, current) =>
            current is OubliettesInitial ||
            current is OubliettesLoading ||
            current is OubliettesEmpty ||
            current is OubliettesError ||
            current is OubliettesLoaded,
        builder: (context, state) => switch (state) {
          OubliettesInitial() || OubliettesLoading() => const Center(
              key: Key('oubliettes_loading'),
              child: CircularProgressIndicator(),
            ),
          OubliettesEmpty() => const NubiaEmptyState(
              key: Key('oubliettes_empty'),
              icon: Icons.inbox_outlined,
              title: 'Aucun document récent',
              subtitle: 'Les documents consultés récemment apparaîtront ici',
            ),
          OubliettesError(:final message) => NubiaErrorWidget(
              key: const Key('oubliettes_error'),
              message: message,
              onRetry: () => context
                  .read<OubliettesBloc>()
                  .add(const OubliettesLoadRequested()),
            ),
          OubliettesLoaded(:final items) => _OubliettesContent(items: items),
          _ => const Center(
              key: Key('oubliettes_loading'),
              child: CircularProgressIndicator(),
            ),
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _OubliettesContent extends StatelessWidget {
  const _OubliettesContent({required this.items});

  final List<OublietteItem> items;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const Key('oubliettes_list'),
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, i) => _OublietteCard(item: items[i]),
    );
  }
}

// ---------------------------------------------------------------------------

class _OublietteCard extends StatelessWidget {
  const _OublietteCard({required this.item});

  final OublietteItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('oubliette_${item.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(item.title),
        subtitle: Text(_dateRel(item.seenAt)),
        onTap: () => context
            .read<OubliettesBloc>()
            .add(OubliettesDocumentRequested(item.id)),
      ),
    );
  }

  static String _dateRel(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays >= 1) return 'il y a ${diff.inDays} j';
    if (diff.inHours >= 1) return 'il y a ${diff.inHours} h';
    return 'il y a ${diff.inMinutes} min';
  }
}
