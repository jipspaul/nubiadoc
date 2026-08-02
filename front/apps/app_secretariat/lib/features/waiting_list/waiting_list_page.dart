import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'waiting_list_bloc.dart';
import 'waiting_list_event.dart';
import 'waiting_list_state.dart';

class WaitingListPage extends StatefulWidget {
  const WaitingListPage({super.key});

  @override
  State<WaitingListPage> createState() => _WaitingListPageState();
}

class _WaitingListPageState extends State<WaitingListPage> {
  Completer<void>? _refreshCompleter;

  @override
  void initState() {
    super.initState();
    context.read<WaitingListBloc>().add(const WaitingListLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('waiting_list_scaffold'),
      appBar: AppBar(
        title: const Text('Liste d\'attente'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<WaitingListBloc>()
                .add(const WaitingListLoadRequested()),
          ),
        ],
      ),
      body: BlocConsumer<WaitingListBloc, WaitingListState>(
        listener: (context, state) {
          if (state is WaitingListLoaded || state is WaitingListError) {
            _refreshCompleter?.complete();
            _refreshCompleter = null;
          }
          if (state is WaitingListOfferSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Créneau proposé avec succès.')),
            );
          }
          if (state is WaitingListOfferError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        builder: (context, state) {
          if (state is WaitingListLoaded ||
              state is WaitingListOfferSuccess ||
              state is WaitingListOfferError) {
            final entries = switch (state) {
              WaitingListLoaded(:final entries) => entries,
              WaitingListOfferError(:final entries) => entries,
              _ => const <WaitingListEntry>[],
            };
            if (entries.isEmpty) {
              return const NubiaEmptyState(
                key: Key('waiting_list_empty'),
                icon: Icons.event_busy,
                title: 'Pas d\'attente',
                subtitle: 'Aucun patient en liste d\'attente',
              );
            }
            return RefreshIndicator(
              key: const Key('waiting_list_refresh'),
              onRefresh: () {
                _refreshCompleter = Completer<void>();
                context
                    .read<WaitingListBloc>()
                    .add(const WaitingListLoadRequested());
                return _refreshCompleter!.future;
              },
              child: ListView.builder(
                key: const Key('waiting_list_list'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: entries.length,
                itemBuilder: (_, i) => _WaitingListTile(entry: entries[i]),
              ),
            );
          }
          if (state is WaitingListError) {
            return NubiaErrorWidget(
              message: state.message,
              onRetry: () => context
                  .read<WaitingListBloc>()
                  .add(const WaitingListLoadRequested()),
            );
          }
          return const _WaitingListSkeleton();
        },
      ),
    );
  }
}

/// Ligne patient : avatar + nom + fenêtre souhaitée + CTA « combler ».
///
/// Cloisonnement : n'affiche que des données non-cliniques (nom, date de
/// demande). Le champ `motif` porté par [WaitingListEntry] est volontairement
/// ignoré par la vue.
class _WaitingListTile extends StatelessWidget {
  const _WaitingListTile({required this.entry});

  final WaitingListEntry entry;

  static String _initials(String name) {
    final trimmed = name.trim();
    return trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
  }

  /// Nom affiché avec repli lisible : le back peut renvoyer une entrée sans
  /// `patient_name` (patient sans fiche). On évite alors l'avatar « ? » et un
  /// titre vide en affichant « Patient » + une référence courte dérivée de
  /// l'identifiant (non-clinique).
  static String _displayName(WaitingListEntry entry) {
    final name = entry.patientName.trim();
    if (name.isNotEmpty) return name;
    final ref =
        _shortRef(entry.patientId.isNotEmpty ? entry.patientId : entry.id);
    return ref.isEmpty ? 'Patient' : 'Patient $ref';
  }

  static String _shortRef(String id) {
    final hex = id.replaceAll('-', '');
    if (hex.isEmpty) return '';
    final start = hex.length >= 4 ? hex.length - 4 : 0;
    return hex.substring(start).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _displayName(entry);
    return ListRow(
      key: Key('waiting_list_row_${entry.id}'),
      leading: NubiaAvatar(initials: _initials(displayName)),
      title: displayName,
      subtitle: 'Fenêtre souhaitée · dès le ${_formatDate(entry.requestedAt)}',
      trailing: NubiaButton(
        key: Key('offer_slot_${entry.id}'),
        label: 'Combler',
        variant: NubiaButtonVariant.secondary,
        size: NubiaButtonSize.sm,
        icon: Icons.calendar_today_outlined,
        onPressed: () => context
            .read<WaitingListBloc>()
            .add(WaitingListOfferSlotRequested(entry.id)),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }
}

/// Skeleton de chargement : quelques lignes shimmer imitant la liste.
class _WaitingListSkeleton extends StatelessWidget {
  const _WaitingListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const Key('waiting_list_skeleton'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 6,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            NubiaSkeletonLoader(width: 40, height: 40, borderRadius: 999),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NubiaSkeletonLoader(width: 160, height: 14),
                  SizedBox(height: 8),
                  NubiaSkeletonLoader(width: 200, height: 12),
                ],
              ),
            ),
            SizedBox(width: 12),
            NubiaSkeletonLoader(width: 96, height: 32),
          ],
        ),
      ),
    );
  }
}
