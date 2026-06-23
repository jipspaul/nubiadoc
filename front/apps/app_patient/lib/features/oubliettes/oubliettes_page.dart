import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'oubliettes_bloc.dart';

class OubliettesPage extends StatelessWidget {
  const OubliettesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OubliettesBloc, OubliettesState>(
      builder: (context, state) {
        if (state is OubliettesInitial || state is OubliettesLoading) {
          return const Center(
            key: Key('oubliettes_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is OubliettesError) {
          return NubiaErrorWidget(
            key: const Key('oubliettes_error'),
            message: state.message,
            onRetry: () => context
                .read<OubliettesBloc>()
                .add(const OubliettesLoadRequested()),
          );
        }
        if (state is OubliettesLoaded) {
          return _OubliettesContent(items: state.items);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _OubliettesContent extends StatelessWidget {
  const _OubliettesContent({required this.items});

  final List<OublietteItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const NubiaEmptyState(
        key: Key('oubliettes_empty'),
        icon: Icons.inbox_outlined,
        title: 'Aucun document récent',
        subtitle: 'Les documents consultés récemment apparaîtront ici',
      );
    }
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
      ),
    );
  }

  static String _dateRel(DateTime date) {
    final now = DateTime(2026, 6, 21);
    final diff = now.difference(date);
    if (diff.inDays >= 1) return 'il y a ${diff.inDays} j';
    if (diff.inHours >= 1) return 'il y a ${diff.inHours} h';
    return 'il y a ${diff.inMinutes} min';
  }
}
