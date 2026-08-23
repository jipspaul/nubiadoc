import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/app_router.dart';
import 'dependents_cubit.dart';

class DependentsPage extends StatelessWidget {
  const DependentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<DependentsCubit>()..load(),
      child: Scaffold(
        appBar: AppBar(
          title: BlocBuilder<DependentsCubit, DependentsState>(
            builder: (context, state) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Mes proches'),
                  if (state is DependentsLoaded)
                    Text(
                      _dependentsSubtitle(
                        state.dependents.length,
                        state.pendingAccessRequests.length,
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              );
            },
          ),
        ),
        body: const _DependentsBody(),
        floatingActionButton: Builder(
          builder: (context) => FloatingActionButton.extended(
            key: const Key('add_dependent_fab'),
            onPressed: () => _openAddSheet(context),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Ajouter'),
          ),
        ),
      ),
    );
  }

  Future<void> _openAddSheet(BuildContext context) async {
    final cubit = context.read<DependentsCubit>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: const _AddDependentSheet(),
      ),
    );
  }
}

String _dependentsSubtitle(int managedCount, int pendingCount) {
  final managedLabel =
      managedCount == 1 ? '1 compte géré' : '$managedCount comptes gérés';
  final pendingLabel = pendingCount == 1
      ? '1 demande en attente'
      : '$pendingCount demandes en attente';
  return '$managedLabel · $pendingLabel';
}

class _DependentsBody extends StatelessWidget {
  const _DependentsBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DependentsCubit, DependentsState>(
      builder: (context, state) {
        if (state is DependentsLoading) {
          return const _DependentsSkeleton();
        }
        if (state is DependentsError) {
          return NubiaErrorWidget(
            message: state.message,
            onRetry: () => context.read<DependentsCubit>().load(),
          );
        }
        if (state is DependentsLoaded) {
          if (state.dependents.isEmpty && state.pendingAccessRequests.isEmpty) {
            return const NubiaEmptyState(
              key: Key('dependents_empty'),
              icon: Icons.people_outline,
              title: 'Aucun proche',
              subtitle: 'Ajoutez un enfant ou un proche que vous gérez.',
            );
          }
          return ListView(
            children: [
              if (state.account != null)
                _SelfAccountCard(account: state.account!),
              if (state.dependents.isNotEmpty) ...[
                const _SectionHeader('COMPTES QUE VOUS GÉREZ'),
                Column(
                  key: const Key('dependents_list'),
                  children: [
                    for (final dependent in state.dependents) ...[
                      _DependentTile(
                        dependent: dependent,
                        disabled: state.mutating,
                        nextAppointmentAt:
                            state.nextAppointmentByDependentId[dependent.id],
                      ),
                      const Divider(height: 1),
                    ],
                  ],
                ),
                if (state.dependents
                    .any((d) => d.relationship == DependentRelationship.enfant))
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: _MajorityNotice(),
                  ),
              ],
              if (state.pendingAccessRequests.isNotEmpty) ...[
                const _SectionHeader('DEMANDES ENVOYÉES'),
                for (final request in state.pendingAccessRequests)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: _PendingRequestTile(
                      request: request,
                      disabled: state.mutating,
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _ExpiryNotice(),
                ),
              ],
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

/// Squelette de chargement de Mes proches, à l'image de `_DocumentsSkeleton`
/// (`documents_page.dart`) : reproduit la forme des cartes proches (avatar
/// rond + deux lignes de texte + zone d'actions) plutôt qu'un spinner centré
/// (maquette design-v2, point 10, #5229).
class _DependentsSkeleton extends StatelessWidget {
  const _DependentsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('dependents_loading'),
      padding: const EdgeInsets.all(16),
      children: const [
        _DependentSkeletonCard(),
        SizedBox(height: 12),
        _DependentSkeletonCard(),
        SizedBox(height: 12),
        _DependentSkeletonCard(),
      ],
    );
  }
}

class _DependentSkeletonCard extends StatelessWidget {
  const _DependentSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return const NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NubiaSkeletonLoader(height: 40, width: 40, borderRadius: 20),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NubiaSkeletonLoader(height: 14, width: 140),
                    SizedBox(height: 8),
                    NubiaSkeletonLoader(height: 12, width: 100),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: NubiaSkeletonLoader(height: 36, borderRadius: 8)),
              SizedBox(width: 12),
              Expanded(child: NubiaSkeletonLoader(height: 36, borderRadius: 8)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Carte « Vous · titulaire » en tête de l'écran (maquette design-v2, point
/// 7, #5228) : situe le patient lui-même avant la liste des comptes gérés,
/// pour poser le cadre « qui gère qui ».
class _SelfAccountCard extends StatelessWidget {
  const _SelfAccountCard({required this.account});

  final PatientAccount account;

  String get _initials {
    final first = account.firstName.trim();
    final last = account.lastName.trim();
    final firstLetter = first.isEmpty ? '' : first[0];
    final lastLetter = last.isEmpty ? '' : last[0];
    return '$firstLetter$lastLetter'.toUpperCase();
  }

  String get _subtitle {
    final age = account.ageInYears;
    return age == null ? 'Vous' : 'Vous · $age ans';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    return NubiaCard(
      key: const Key('self_account_card'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: NubiaColors.brand600,
            child: Text(
              _initials,
              style: theme.textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.displayName, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  _subtitle,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: tokens.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const StatusPill(
            label: 'Titulaire',
            variant: StatusPillVariant.neutral,
          ),
        ],
      ),
    );
  }
}

/// En-tête de section majuscule gris `--n400` (maquette design-v2, #5251) :
/// distingue les comptes gérés des demandes d'invitation envoyées.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.labelSmall?.copyWith(
          color: tokens.textTertiary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Encart « shield » sous la liste des comptes gérés, rappelant que l'accès
/// du parent à un enfant mineur cesse à sa majorité (maquette design-v2,
/// encart « Un mineur devient majeur », #5230) : n'affiché que si au moins
/// un proche géré est un enfant.
class _MajorityNotice extends StatelessWidget {
  const _MajorityNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    return NubiaCard(
      key: const Key('majority_notice'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 18, color: tokens.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Vous gérez les rendez-vous et les documents de ces comptes. '
              "À sa majorité, votre enfant reprendra son propre accès et "
              "vous perdrez ce droit — la loi l'impose.",
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: tokens.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Encart « info » sous la liste des demandes envoyées, rappelant
/// l'expiration à 30 jours d'une invitation proche adulte sans réponse.
class _ExpiryNotice extends StatelessWidget {
  const _ExpiryNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    return NubiaCard(
      key: const Key('access_request_expiry_notice'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule, size: 18, color: tokens.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Une demande sans réponse expire au bout de 30 jours. '
              'Vous pourrez en envoyer une nouvelle.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: tokens.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

const _weekdays = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

const _months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

/// Formate un horodatage de RDV en « jeudi 14 août, 16:30 » (heure locale —
/// cf. #4620/#4618 : un horodatage UTC lu sans `.toLocal()` décale l'heure
/// affichée).
String _formatNextAppointment(DateTime at) {
  final dt = at.toLocal();
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '${_weekdays[dt.weekday - 1]} ${dt.day} ${_months[dt.month - 1]}, $h:$m';
}

enum _DependentMenuAction { delete }

class _DependentTile extends StatelessWidget {
  const _DependentTile({
    required this.dependent,
    required this.disabled,
    this.nextAppointmentAt,
  });

  final Dependent dependent;
  final bool disabled;
  final DateTime? nextAppointmentAt;

  String get _relationLabel {
    switch (dependent.relationship) {
      case DependentRelationship.enfant:
        return 'Enfant';
      case DependentRelationship.conjoint:
        return 'Conjoint';
      case DependentRelationship.autre:
        return 'Proche';
    }
  }

  /// Icône + libellé du fondement juridique de la gestion — distincts par
  /// [DependentRelationship] (maquette design-v2, encart « Un mineur devient
  /// majeur », #5230) : un enfant mineur est géré de plein droit, un proche
  /// adulte ne l'est que par mandat explicite (cf. [AccessRequest]).
  (IconData, String) get _legalBasis {
    switch (dependent.relationship) {
      case DependentRelationship.enfant:
        return (Icons.family_restroom, 'Représentant légal');
      case DependentRelationship.conjoint:
      case DependentRelationship.autre:
        return (Icons.handshake_outlined, 'Mandataire');
    }
  }

  String get _initials {
    final first = dependent.firstName.trim();
    final last = dependent.lastName.trim();
    final firstLetter = first.isEmpty ? '' : first[0];
    final lastLetter = last.isEmpty ? '' : last[0];
    return '$firstLetter$lastLetter'.toUpperCase();
  }

  String get _subtitle {
    final age = dependent.ageInYears;
    return age == null ? _relationLabel : '$_relationLabel · $age ans';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    return NubiaCard(
      key: Key('dependent_${dependent.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NubiaAvatar(initials: _initials, radius: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dependent.displayName,
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Tooltip(
                          message: _legalBasis.$2,
                          child: Icon(_legalBasis.$1,
                              size: 14, color: tokens.textTertiary),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _subtitle,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: tokens.textTertiary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (dependent.hasParentalAccessExpired) ...[
                const StatusPill(
                  key: Key('parental_access_expired_pill'),
                  label: 'Majorité atteinte',
                  variant: StatusPillVariant.warning,
                  icon: Icons.gpp_maybe_outlined,
                ),
                const SizedBox(width: 8),
              ],
              PopupMenuButton<_DependentMenuAction>(
                key: Key('dependent_menu_${dependent.id}'),
                icon: Icon(Icons.more_horiz, color: tokens.textTertiary),
                enabled: !disabled,
                onSelected: (action) {
                  switch (action) {
                    case _DependentMenuAction.delete:
                      _confirmDelete(context);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    key: Key('delete_dependent_${dependent.id}'),
                    value: _DependentMenuAction.delete,
                    child: const Text('Supprimer'),
                  ),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Divider(height: 1, color: tokens.borderSubtle),
          ),
          const SizedBox(height: 12),
          if (nextAppointmentAt != null)
            Row(
              children: [
                const Icon(Icons.event, size: 18, color: NubiaColors.brand600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Prochain RDV ${_formatNextAppointment(nextAppointmentAt!)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                GestureDetector(
                  key: Key('dependent_${dependent.id}_next_appointment_cta'),
                  onTap: () => context.push(AppRouter.mesRdv),
                  child: Text(
                    'Voir',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: NubiaColors.brand700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Icon(Icons.calendar_today, size: 18, color: tokens.textTertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Aucun rendez-vous à venir',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: tokens.textTertiary),
                  ),
                ),
                GestureDetector(
                  key: Key('dependent_${dependent.id}_plan_appointment_cta'),
                  onTap: () => context.push(AppRouter.book),
                  child: Text(
                    'Planifier',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: NubiaColors.brand700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          if (dependent.hasParentalAccessExpired)
            _ParentalAccessExpiredNotice(firstName: dependent.firstName)
          else
            Row(
              children: [
                Expanded(
                  child: NubiaButton(
                    label: 'Prendre RDV',
                    icon: Icons.event_available,
                    variant: NubiaButtonVariant.secondary,
                    onPressed: () => context.push(AppRouter.book),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: NubiaButton(
                    label: 'Documents',
                    icon: Icons.folder,
                    variant: NubiaButtonVariant.secondary,
                    onPressed: () => context.push(AppRouter.documents),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer ce proche ?'),
        content: Text(
            '${dependent.firstName} ${dependent.lastName} ne sera plus rattaché à votre compte.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Retirer')),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      context.read<DependentsCubit>().remove(dependent.id);
    }
  }
}

/// Remplace les actions « Prendre RDV »/« Documents » une fois la majorité
/// atteinte : la loi impose la fin de l'accès du parent au dossier de son
/// enfant à 18 ans (maquette design-v2, encart « Un mineur devient majeur »,
/// #5230) — [DependentsCubit] ne gère pas la ré-invitation en proche adulte,
/// ce message oriente donc vers l'ajout d'un proche adulte classique.
class _ParentalAccessExpiredNotice extends StatelessWidget {
  const _ParentalAccessExpiredNotice({required this.firstName});

  final String firstName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      key: const Key('parental_access_expired_notice'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 18, color: NubiaColors.n400),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$firstName a atteint sa majorité : vous n\'avez plus accès à '
            'son dossier. Il peut vous inviter comme proche adulte s\'il '
            'souhaite vous en donner l\'accès.',
            style: theme.textTheme.bodySmall?.copyWith(color: NubiaColors.n500),
          ),
        ),
      ],
    );
  }
}

/// « Envoyée hier », sinon « Envoyée le JJ/MM » — [AccessRequest] ne
/// conserve que la date d'envoi, pas l'adresse du destinataire (cf.
/// #5259 : le domaine expose état/canal/date, pas les coordonnées).
String _relativeSentAt(DateTime sentAt) {
  final dt = sentAt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final sentDay = DateTime(dt.year, dt.month, dt.day);
  final daysAgo = today.difference(sentDay).inDays;
  if (daysAgo == 0) return "Envoyée aujourd'hui";
  if (daysAgo == 1) return 'Envoyée hier';
  return 'Envoyée le '
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
}

/// Carte « demande en attente » (maquette design-v2, #5252) : invitation
/// proche adulte envoyée non encore répondue, avec actions rapides
/// Relancer / Annuler.
class _PendingRequestTile extends StatelessWidget {
  const _PendingRequestTile({
    required this.request,
    required this.disabled,
  });

  final AccessRequest request;
  final bool disabled;

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
    final first = request.firstName.trim();
    final last = request.lastName.trim();
    final firstLetter = first.isEmpty ? '' : first[0];
    final lastLetter = last.isEmpty ? '' : last[0];
    return '$firstLetter$lastLetter'.toUpperCase();
  }

  String get _channelLabel =>
      request.channel == AccessRequestChannel.sms ? 'par SMS' : 'par email';

  String get _statusLine {
    final sentAt = request.sentAt;
    final sentLabel = sentAt == null ? 'Envoyée' : _relativeSentAt(sentAt);
    return '$sentLabel $_channelLabel';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    return SizedBox(
      key: Key('pending_request_${request.id}'),
      width: double.infinity,
      child: CustomPaint(
        foregroundPainter: const _DashedRRectPainter(
          color: NubiaColors.n300,
          radius: 12,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: NubiaColors.n50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: NubiaColors.n200,
                      child: Text(
                        _initials,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: NubiaColors.n600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(request.displayName,
                              style: theme.textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            _relationLabel,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: tokens.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const StatusPill(
                      label: 'En attente',
                      variant: StatusPillVariant.warning,
                      icon: Icons.schedule,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.mail, size: 18, color: tokens.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusLine,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: tokens.textTertiary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: NubiaButton(
                        key: Key('resend_access_request_${request.id}'),
                        label: 'Relancer',
                        icon: Icons.send,
                        variant: NubiaButtonVariant.secondary,
                        onPressed: disabled
                            ? null
                            : () => context
                                .read<DependentsCubit>()
                                .resend(request.id),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: NubiaButton(
                        key: Key('cancel_access_request_${request.id}'),
                        label: 'Annuler',
                        icon: Icons.close,
                        variant: NubiaButtonVariant.secondary,
                        onPressed: disabled
                            ? null
                            : () => context
                                .read<DependentsCubit>()
                                .cancel(request.id),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bordure pointillée d'un rectangle arrondi — Flutter n'a pas de
/// `BorderStyle.dashed` natif (maquette, carte « dep pend »).
class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const _dashWidth = 4.0;
  static const _dashGap = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _AddDependentSheet extends StatefulWidget {
  const _AddDependentSheet();

  @override
  State<_AddDependentSheet> createState() => _AddDependentSheetState();
}

class _AddDependentSheetState extends State<_AddDependentSheet> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  DependentRelationship _relationship = DependentRelationship.enfant;

  /// Date de naissance du proche — n'exploitée (côté domaine) que pour un
  /// enfant : c'est elle qui pilote la bascule de majorité (#5230). Un
  /// proche adulte gère son propre profil après acceptation de l'invitation.
  DateTime? _dateOfBirth;

  /// Périmètre proposé par le demandeur pour une invitation proche adulte —
  /// point de départ que l'invité pourra restreindre à l'acceptation (note 2
  /// de la maquette, cf. `_AdjustScopeCard` dans `incoming_request_page.dart`).
  bool _scopeAppointments = true;
  bool _scopeDocuments = true;
  bool _scopeMessages = false;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  bool get _emailValid => _emailRe.hasMatch(_email.text.trim());

  bool get _valid {
    if (_firstName.text.trim().isEmpty || _lastName.text.trim().isEmpty) {
      return false;
    }
    if (!_isInvitation && _dateOfBirth == null) return false;
    return !_isInvitation || _emailValid;
  }

  /// Un proche adulte (conjoint/autre) passe par une invitation — demande
  /// d'accès qu'il devra accepter — alors qu'un enfant est ajouté
  /// directement comme compte géré (maquette design-v2, #5250).
  bool get _isInvitation => _relationship != DependentRelationship.enfant;

  String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';

  Future<void> _pickDateOfBirth(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(DateTime.now().year - 10),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('fr'),
    );
    if (picked != null) {
      setState(() => _dateOfBirth = picked);
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ajouter un proche', style: theme.textTheme.titleMedium),
            if (_isInvitation) ...[
              const SizedBox(height: 2),
              Text(
                'Un adulte doit accepter votre demande',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: tokens.textTertiary),
              ),
            ],
            const SizedBox(height: 16),
            NubiaTextField(
              key: const Key('dependent_first_name'),
              controller: _firstName,
              label: 'Prénom',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            NubiaTextField(
              key: const Key('dependent_last_name'),
              controller: _lastName,
              label: 'Nom',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            SegmentedControl(
              key: const Key('dependent_relationship'),
              segments: const ['Enfant', 'Conjoint', 'Autre'],
              selectedIndex: _relationship.index,
              onChanged: (i) => setState(
                  () => _relationship = DependentRelationship.values[i]),
            ),
            if (!_isInvitation) ...[
              const SizedBox(height: 12),
              _DependentDobField(
                key: const Key('dependent_date_of_birth'),
                value: _dateOfBirth != null
                    ? _formatDate(_dateOfBirth!)
                    : null,
                onTap: () => _pickDateOfBirth(context),
              ),
            ],
            if (_isInvitation) ...[
              const SizedBox(height: 12),
              const _WhyRequestNotice(),
              const SizedBox(height: 12),
              NubiaTextField(
                key: const Key('dependent_email'),
                controller: _email,
                variant: NubiaTextFieldVariant.email,
                label: 'Où lui envoyer la demande',
                hint: 'emile.martin@email.fr',
                borderRadius: 12,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              _ProposedScopeCard(
                appointments: _scopeAppointments,
                documents: _scopeDocuments,
                messages: _scopeMessages,
                onAppointmentsChanged: (v) =>
                    setState(() => _scopeAppointments = v),
                onDocumentsChanged: (v) => setState(() => _scopeDocuments = v),
                onMessagesChanged: (v) => setState(() => _scopeMessages = v),
              ),
            ],
            const SizedBox(height: 24),
            NubiaButton(
              key: const Key('save_dependent_button'),
              label: _isInvitation ? 'Envoyer la demande' : 'Ajouter',
              icon: _isInvitation ? Icons.send : null,
              onPressed: !_valid
                  ? null
                  : () {
                      context.read<DependentsCubit>().add(
                            firstName: _firstName.text.trim(),
                            lastName: _lastName.text.trim(),
                            birthDate: _dateOfBirth,
                            relationship: _relationship,
                          );
                      Navigator.pop(context);
                    },
            ),
            if (_isInvitation) ...[
              const SizedBox(height: 12),
              _InvitationReassuranceNotice(
                firstName: _firstName.text.trim(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sélecteur de date de naissance de l'enfant ajouté — seule donnée qui
/// permette de piloter la bascule de majorité côté domaine (#5230).
class _DependentDobField extends StatelessWidget {
  const _DependentDobField({
    super.key,
    required this.value,
    required this.onTap,
  });

  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        isEmpty: value == null,
        decoration: const InputDecoration(
          labelText: 'Date de naissance',
          hintText: 'JJ/MM/AAAA',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.calendar_today_outlined),
        ),
        child: value != null
            ? Text(value!, style: Theme.of(context).textTheme.bodyMedium)
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// Carte « Ce que vous pourrez faire » (maquette design-v2, #5248) : le
/// périmètre proposé par le demandeur pour l'invitation d'un proche adulte.
class _ProposedScopeCard extends StatelessWidget {
  const _ProposedScopeCard({
    required this.appointments,
    required this.documents,
    required this.messages,
    required this.onAppointmentsChanged,
    required this.onDocumentsChanged,
    required this.onMessagesChanged,
  });

  final bool appointments;
  final bool documents;
  final bool messages;
  final ValueChanged<bool> onAppointmentsChanged;
  final ValueChanged<bool> onDocumentsChanged;
  final ValueChanged<bool> onMessagesChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    return NubiaCard(
      key: const Key('proposed_scope_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CE QUE VOUS POURREZ FAIRE',
            style: theme.textTheme.labelSmall?.copyWith(
              color: tokens.textTertiary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 12),
          _ScopeRow(
            rowKey: const Key('proposed_scope_toggle_appointments'),
            icon: Icons.event_available,
            title: 'Ses rendez-vous',
            subtitle: 'Voir, prendre, annuler',
            value: appointments,
            onChanged: onAppointmentsChanged,
          ),
          const SizedBox(height: 12),
          _ScopeRow(
            rowKey: const Key('proposed_scope_toggle_documents'),
            icon: Icons.folder,
            title: 'Ses documents',
            subtitle: 'Ordonnances, devis, factures',
            value: documents,
            onChanged: onDocumentsChanged,
          ),
          const SizedBox(height: 12),
          _ScopeRow(
            rowKey: const Key('proposed_scope_toggle_messages'),
            icon: Icons.chat_bubble,
            title: 'Ses messages avec le cabinet',
            value: messages,
            onChanged: onMessagesChanged,
          ),
        ],
      ),
    );
  }
}

/// Ligne icône + titre (+ sous-titre optionnel) + [NubiaToggle], utilisée par
/// [_ProposedScopeCard].
class _ScopeRow extends StatelessWidget {
  const _ScopeRow({
    required this.rowKey,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Key rowKey;
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: tokens.textTertiary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.bodyLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: tokens.textTertiary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        NubiaToggle(key: rowKey, value: value, onChanged: onChanged),
      ],
    );
  }
}

/// Encart « Pourquoi une demande ? » sous le sélecteur de lien, expliquant
/// pourquoi un proche adulte (conjoint/autre) passe par une invitation
/// alors qu'un enfant mineur est ajouté directement (maquette design-v2,
/// patient-invitation-proche-adulte, #5246).
class _WhyRequestNotice extends StatelessWidget {
  const _WhyRequestNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NubiaCard(
      key: const Key('why_request_notice'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.handshake, size: 20, color: NubiaColors.brand700),
              const SizedBox(width: 8),
              Text('Pourquoi une demande ?', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: theme.textTheme.bodySmall,
              children: const [
                TextSpan(
                  text: 'Vous gérez un enfant mineur de plein droit. Pour un '
                      'adulte, la loi exige ',
                ),
                TextSpan(
                  text: 'son accord',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: ' : nous lui envoyons une demande qu\'il peut '
                      'accepter ou refuser.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Encart de réassurance sous le CTA d'invitation d'un proche adulte,
/// rappelant que l'invité garde la main sur l'accès accordé (maquette
/// design-v2, #5250).
class _InvitationReassuranceNotice extends StatelessWidget {
  const _InvitationReassuranceNotice({required this.firstName});

  final String firstName;

  @override
  Widget build(BuildContext context) {
    final name = firstName.isEmpty ? 'Votre proche' : firstName;
    return NubiaCard(
      key: const Key('invitation_reassurance_notice'),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield, size: 20, color: NubiaColors.n400),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "$name choisira ce qu'il vous autorise, et pourra retirer cet "
              'accès à tout moment depuis son profil. Vous en serez informé.',
              style: const TextStyle(fontSize: 11.5, color: NubiaColors.n500),
            ),
          ),
        ],
      ),
    );
  }
}
