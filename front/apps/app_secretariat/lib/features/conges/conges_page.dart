import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'conges_bloc.dart';
import 'conges_event.dart';
import 'conges_state.dart';
import 'widgets/leave_request_row.dart';

/// Écran « Congés » (#7143/#7144) : validation manager des demandes de
/// congé du cabinet — file d'attente par défaut, historique consultable.
/// `Approuver`/`Refuser` sont réservés admin/manager côté back ; un 403
/// (secrétaire simple) s'affiche en snackbar plutôt que de masquer l'écran,
/// qui reste consultable par tout rôle pro (#7143).
class CongesPage extends StatelessWidget {
  const CongesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('conges_scaffold'),
      appBar: AppBar(title: const Text('Congés')),
      body: const _CongesBody(),
    );
  }
}

class _CongesBody extends StatefulWidget {
  const _CongesBody();

  @override
  State<_CongesBody> createState() => _CongesBodyState();
}

class _CongesBodyState extends State<_CongesBody> {
  bool _showHistory = false;
  Map<String, String> _memberNames = const {};

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final result = await GetIt.instance<ListMembersUseCase>()();
    if (!mounted) return;
    result.fold(
      (_) {},
      (members) => setState(() {
        _memberNames = {for (final m in members) m.id: m.fullName};
      }),
    );
  }

  void _reload(BuildContext context) {
    context.read<CongesBloc>().add(
        CongesLoadRequested(status: _showHistory ? null : 'pending'));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<CongesBloc, CongesState>(
      listenWhen: (_, current) =>
          current is CongesLoaded && current.actionError != null,
      listener: (context, state) {
        if (state is CongesLoaded && state.actionError != null) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            state.actionError!,
            Directionality.of(context),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.actionError!)),
          );
        }
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('conges_filter_pending'),
                  label: const Text('En attente'),
                  selected: !_showHistory,
                  onSelected: (_) {
                    setState(() => _showHistory = false);
                    _reload(context);
                  },
                ),
                ChoiceChip(
                  key: const Key('conges_filter_history'),
                  label: const Text('Toutes'),
                  selected: _showHistory,
                  onSelected: (_) {
                    setState(() => _showHistory = true);
                    _reload(context);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: BlocBuilder<CongesBloc, CongesState>(
              builder: (context, state) {
                return switch (state) {
                  CongesLoading() => const Center(
                      key: Key('conges_loading'),
                      child: CircularProgressIndicator(),
                    ),
                  CongesError(:final message) => NubiaErrorWidget(
                      key: const Key('conges_error'),
                      message: message,
                      onRetry: () => _reload(context),
                    ),
                  CongesLoaded(:final requests) when requests.isEmpty =>
                    const NubiaEmptyState(
                      key: Key('conges_empty'),
                      icon: Icons.beach_access_outlined,
                      title: 'Aucune demande de congé',
                    ),
                  CongesLoaded(:final requests) => ListView.builder(
                      key: const Key('conges_list'),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: requests.length,
                      itemBuilder: (_, i) {
                        final request = requests[i];
                        return LeaveRequestRow(
                          leaveRequest: request,
                          requesterName: _memberNames[request.userId],
                          onApprove: () => context.read<CongesBloc>().add(
                              CongesDecideRequested(
                                  leaveRequestId: request.id, approve: true)),
                          onReject: () => context.read<CongesBloc>().add(
                              CongesDecideRequested(
                                  leaveRequestId: request.id,
                                  approve: false)),
                        );
                      },
                    ),
                };
              },
            ),
          ),
        ],
      ),
    );
  }
}
