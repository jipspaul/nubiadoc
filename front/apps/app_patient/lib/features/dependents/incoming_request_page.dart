import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'incoming_request_cubit.dart';

/// Écran « Décider » (design-v2, #5258) : l'invité accepte ou refuse une
/// invitation « proche » reçue d'un autre compte patient.
///
/// [request] est fourni par l'appelant (déjà chargée en amont — notification
/// ou lien reçu) : il n'existe pas de endpoint de lecture par id, seulement
/// `GET /v1/account/access-requests` (liste, côté demandeur).
class IncomingRequestPage extends StatelessWidget {
  const IncomingRequestPage({super.key, required this.request});

  final AccessRequest request;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<IncomingRequestCubit>()..load(request),
      child: Scaffold(
        appBar: AppBar(title: const Text('Décider')),
        body: const _IncomingRequestBody(),
      ),
    );
  }
}

class _IncomingRequestBody extends StatelessWidget {
  const _IncomingRequestBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<IncomingRequestCubit, IncomingRequestState>(
      builder: (context, state) {
        if (state is! IncomingRequestLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RequesterCard(request: state.request),
              const SizedBox(height: 24),
              if (state.errorMessage != null) ...[
                Text(
                  state.errorMessage!,
                  key: const Key('incoming_request_error'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              if (state.request.status == AccessRequestStatus.envoyee) ...[
                _AdjustScopeCard(scope: state.scope),
                const SizedBox(height: 16),
                _DecisionActions(state: state),
              ] else
                _DecisionOutcome(status: state.request.status),
            ],
          ),
        );
      },
    );
  }
}

/// Identité du demandeur — contexte minimal, le détail du périmètre proposé
/// (« Ce qu'elle pourrait faire ») est hors scope ici (#5256). Son
/// ajustement est porté par [_AdjustScopeCard] (#5257).
class _RequesterCard extends StatelessWidget {
  const _RequesterCard({required this.request});

  final AccessRequest request;

  String get _relationLabel {
    switch (request.relationship) {
      case DependentRelationship.enfant:
        return 'Enfant';
      case DependentRelationship.conjoint:
        return 'Conjoint';
      case DependentRelationship.autre:
        return 'Proche';
    }
  }

  String get _initials {
    final first = request.firstName.isNotEmpty ? request.firstName[0] : '';
    final last = request.lastName.isNotEmpty ? request.lastName[0] : '';
    return '$first$last'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    return NubiaCard(
      key: const Key('incoming_request_requester_card'),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: tokens.primarySubtleBg,
            foregroundColor: tokens.primarySubtleFg,
            child: Text(_initials),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.displayName, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  _relationLabel,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte « Ajuster avant d'accepter » (#5257) : l'invité restreint le
/// périmètre proposé via des toggles avant d'accepter. Note 2 : c'est
/// l'invité qui décide de l'étendue finale, pas le demandeur — le périmètre
/// envoyé lors de l'acceptation est celui affiché ici.
class _AdjustScopeCard extends StatelessWidget {
  const _AdjustScopeCard({required this.scope});

  final Set<AccessRight> scope;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    final cubit = context.read<IncomingRequestCubit>();
    return NubiaCard(
      key: const Key('adjust_scope_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ajuster avant d\'accepter', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.event_available, size: 20, color: tokens.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: NubiaToggle(
                  key: const Key('adjust_scope_toggle_rendez_vous'),
                  value: scope.contains(AccessRight.rendezVous),
                  label: 'Mes rendez-vous',
                  onChanged: (granted) =>
                      cubit.setScopeRight(AccessRight.rendezVous, granted),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Icon(Icons.folder, size: 20, color: tokens.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: NubiaToggle(
                  key: const Key('adjust_scope_toggle_documents'),
                  value: scope.contains(AccessRight.documents),
                  label: 'Mes documents',
                  onChanged: (granted) =>
                      cubit.setScopeRight(AccessRight.documents, granted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bloc d'actions Accepter / Refuser + encart de révocation (#5258).
class _DecisionActions extends StatelessWidget {
  const _DecisionActions({required this.state});

  final IncomingRequestLoaded state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<IncomingRequestCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NubiaButton(
          key: const Key('accept_access_request_button'),
          label: 'Accepter',
          icon: Icons.check,
          size: NubiaButtonSize.lg,
          onPressed: state.mutating ? null : () => cubit.accept(state.scope),
        ),
        const SizedBox(height: 8),
        NubiaButton(
          key: const Key('refuse_access_request_button'),
          label: 'Refuser',
          icon: Icons.close,
          variant: NubiaButtonVariant.secondary,
          size: NubiaButtonSize.lg,
          onPressed: state.mutating ? null : () => cubit.refuse(),
        ),
        const SizedBox(height: 16),
        _RevocationNotice(requesterFirstName: state.request.firstName),
      ],
    );
  }
}

/// Encart « info » rappelant la révocation symétrique et notifiée (#5259
/// note 5) : l'invité retire l'accès depuis son propre profil, à tout
/// moment ; le demandeur en est informé.
class _RevocationNotice extends StatelessWidget {
  const _RevocationNotice({required this.requesterFirstName});

  final String requesterFirstName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    return NubiaCard(
      key: const Key('revocation_notice'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock, size: 18, color: tokens.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Vous pourrez retirer cet accès à tout moment, depuis '
              'Profil → Mes proches. $requesterFirstName en sera informé.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: tokens.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// État terminal (déjà décidé) — la demande n'est plus `envoyee`, les
/// actions n'ont plus de sens.
class _DecisionOutcome extends StatelessWidget {
  const _DecisionOutcome({required this.status});

  final AccessRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, variant) = switch (status) {
      AccessRequestStatus.acceptee => ('Acceptée', StatusPillVariant.success),
      AccessRequestStatus.refusee => ('Refusée', StatusPillVariant.error),
      AccessRequestStatus.expiree => ('Expirée', StatusPillVariant.neutral),
      AccessRequestStatus.envoyee => ('En attente', StatusPillVariant.info),
    };
    return Center(
      child: StatusPill(
          key: const Key('incoming_request_outcome'),
          label: label,
          variant: variant),
    );
  }
}
