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
        appBar: AppBar(title: const Text('Mes proches')),
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

class _DependentsBody extends StatelessWidget {
  const _DependentsBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DependentsCubit, DependentsState>(
      builder: (context, state) {
        if (state is DependentsLoading) {
          return const Center(child: CircularProgressIndicator());
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
              if (state.pendingAccessRequests.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Demandes envoyées',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
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

  String get _initials {
    final first = dependent.firstName.trim();
    final last = dependent.lastName.trim();
    final firstLetter = first.isEmpty ? '' : first[0];
    final lastLetter = last.isEmpty ? '' : last[0];
    return '$firstLetter$lastLetter'.toUpperCase();
  }

  int? get _age {
    final dob = dependent.dateOfBirth;
    if (dob == null) return null;
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  String get _subtitle {
    final age = _age;
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
                    Text(
                      _subtitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: tokens.textTertiary),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: Key('delete_dependent_${dependent.id}'),
                icon: const Icon(Icons.delete_outline),
                onPressed: disabled ? null : () => _confirmDelete(context),
              ),
            ],
          ),
          if (nextAppointmentAt != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Divider(height: 1, color: tokens.borderSubtle),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.event, size: 18, color: tokens.textTertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Prochain RDV ${_formatNextAppointment(nextAppointmentAt!)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
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
  DependentRelationship _relationship = DependentRelationship.enfant;

  bool get _valid =>
      _firstName.text.trim().isNotEmpty && _lastName.text.trim().isNotEmpty;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ajouter un proche',
              style: Theme.of(context).textTheme.titleMedium),
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
          DropdownButtonFormField<DependentRelationship>(
            key: const Key('dependent_relationship'),
            initialValue: _relationship,
            decoration: const InputDecoration(
              labelText: 'Lien',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                  value: DependentRelationship.enfant, child: Text('Enfant')),
              DropdownMenuItem(
                  value: DependentRelationship.conjoint,
                  child: Text('Conjoint')),
              DropdownMenuItem(
                  value: DependentRelationship.autre, child: Text('Proche')),
            ],
            onChanged: (v) =>
                setState(() => _relationship = v ?? _relationship),
          ),
          const SizedBox(height: 24),
          NubiaButton(
            key: const Key('save_dependent_button'),
            label: 'Ajouter',
            onPressed: !_valid
                ? null
                : () {
                    context.read<DependentsCubit>().add(
                          firstName: _firstName.text.trim(),
                          lastName: _lastName.text.trim(),
                          relationship: _relationship,
                        );
                    Navigator.pop(context);
                  },
          ),
        ],
      ),
    );
  }
}
