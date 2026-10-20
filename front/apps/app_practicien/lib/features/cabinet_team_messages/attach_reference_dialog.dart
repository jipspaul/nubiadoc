//! Dialogue « Joindre un patient, un devis… » du composeur (#5131/#8228) :
//! recherche un objet réel du produit à attacher au message en cours de
//! rédaction. #6702/#8181 grisait ce bouton faute d'endpoint ; #8221 a livré
//! la moitié API (`POST .../messages` accepte `reference`), cette boîte
//! livre la moitié front qui manquait encore.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Types proposés à l'attachement : sous-ensemble de
/// [CabinetTeamMessageReferenceType] couvert par un parcours de recherche
/// côté `app_practicien`. `agendaSlot` n'a pas (encore) de sélecteur de
/// créneau dédié et reste hors périmètre, comme le bon de labo côté
/// `app_secretariat` (cf. son propre dialogue).
const _kAttachableTypes = [
  CabinetTeamMessageReferenceType.patient,
  CabinetTeamMessageReferenceType.devis,
  CabinetTeamMessageReferenceType.labWorkOrder,
  CabinetTeamMessageReferenceType.stockRequest,
];

String _typeLabel(CabinetTeamMessageReferenceType type) => switch (type) {
      CabinetTeamMessageReferenceType.patient => 'Patient',
      CabinetTeamMessageReferenceType.devis => 'Devis',
      CabinetTeamMessageReferenceType.labWorkOrder => 'Bon de labo',
      CabinetTeamMessageReferenceType.stockRequest => 'Demande de stock',
      CabinetTeamMessageReferenceType.agendaSlot => 'Créneau',
    };

IconData _typeIcon(CabinetTeamMessageReferenceType type) => switch (type) {
      CabinetTeamMessageReferenceType.patient => Icons.person_outline,
      CabinetTeamMessageReferenceType.devis => Icons.description_outlined,
      CabinetTeamMessageReferenceType.labWorkOrder =>
        Icons.precision_manufacturing,
      CabinetTeamMessageReferenceType.stockRequest => Icons.inventory_2,
      CabinetTeamMessageReferenceType.agendaSlot => Icons.calendar_month,
    };

/// Ouvre le dialogue, retourne la référence choisie ou `null` si annulé.
Future<CabinetTeamMessageReference?> showAttachReferenceDialog(
  BuildContext context,
) {
  return showDialog<CabinetTeamMessageReference>(
    context: context,
    builder: (dialogContext) => Dialog(
      key: const Key('attach_reference_dialog'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SizedBox(
          height: 520,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _AttachReferenceBody(),
          ),
        ),
      ),
    ),
  );
}

enum _Status { loading, loaded, error }

class _AttachReferenceBody extends StatefulWidget {
  const _AttachReferenceBody();

  @override
  State<_AttachReferenceBody> createState() => _AttachReferenceBodyState();
}

class _AttachReferenceBodyState extends State<_AttachReferenceBody> {
  CabinetTeamMessageReferenceType _type =
      CabinetTeamMessageReferenceType.patient;
  _Status _status = _Status.loading;
  List<CabinetTeamMessageReference> _results = const [];
  Timer? _debounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _selectType(CabinetTeamMessageReferenceType type) {
    if (type == _type) return;
    setState(() => _type = type);
    _search(_query);
  }

  void _onChanged(String query) {
    _query = query;
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 300), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() => _status = _Status.loading);
    final trimmed = query.trim().toLowerCase();
    try {
      final results = await switch (_type) {
        CabinetTeamMessageReferenceType.patient => _searchPatients(trimmed),
        CabinetTeamMessageReferenceType.devis => _searchQuotes(trimmed),
        CabinetTeamMessageReferenceType.labWorkOrder =>
          _searchLabWorkOrders(trimmed),
        CabinetTeamMessageReferenceType.stockRequest =>
          _searchStockRequests(trimmed),
        CabinetTeamMessageReferenceType.agendaSlot =>
          Future.value(const <CabinetTeamMessageReference>[]),
      };
      if (!mounted) return;
      setState(() {
        _results = results;
        _status = _Status.loaded;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _Status.error);
    }
  }

  Future<List<CabinetTeamMessageReference>> _searchPatients(
    String query,
  ) async {
    final either = await GetIt.instance<ListCabinetPatientsUseCase>()(
      q: query.isEmpty ? null : query,
    );
    return either.fold(
      (failure) => throw failure,
      (patients) => patients
          .map((p) => CabinetTeamMessageReference(
                type: CabinetTeamMessageReferenceType.patient,
                targetId: p.id,
                title: '${p.firstName} ${p.lastName}',
                subtitle: 'Dossier administratif',
              ))
          .toList(),
    );
  }

  Future<List<CabinetTeamMessageReference>> _searchQuotes(
    String query,
  ) async {
    final either =
        await GetIt.instance<ListCabinetQuotesUseCase>()(limit: 50);
    return either.fold(
      (failure) => throw failure,
      (quotes) => quotes
          .where((q) =>
              query.isEmpty ||
              q.quoteRef.toLowerCase().contains(query) ||
              q.patientName.toLowerCase().contains(query))
          .map((q) => CabinetTeamMessageReference(
                type: CabinetTeamMessageReferenceType.devis,
                targetId: q.id,
                title: 'Devis ${q.quoteRef}',
                subtitle: '${q.patientName} · ${_quoteStatusLabel(q.status)}',
              ))
          .toList(),
    );
  }

  Future<List<CabinetTeamMessageReference>> _searchLabWorkOrders(
    String query,
  ) async {
    final either = await GetIt.instance<ListLabWorkOrdersUseCase>()();
    return either.fold(
      (failure) => throw failure,
      (orders) => orders
          .where((o) =>
              query.isEmpty ||
              o.patientDisplayName.toLowerCase().contains(query) ||
              o.labName.toLowerCase().contains(query) ||
              (o.workNature?.toLowerCase().contains(query) ?? false))
          .map((o) => CabinetTeamMessageReference(
                type: CabinetTeamMessageReferenceType.labWorkOrder,
                targetId: o.id,
                title: [
                  o.workNature ?? 'Bon de labo',
                  if (o.toothFdi != null) 'dent ${o.toothFdi}',
                ].join(' · '),
                subtitle: '${o.labName} · ${_labStatusLabel(o.status)}',
              ))
          .toList(),
    );
  }

  Future<List<CabinetTeamMessageReference>> _searchStockRequests(
    String query,
  ) async {
    final either = await GetIt.instance<ListStockRequestsUseCase>()();
    return either.fold(
      (failure) => throw failure,
      (requests) => requests
          .where((r) =>
              query.isEmpty ||
              (r.pharmacy?.name.toLowerCase().contains(query) ?? false) ||
              r.items.any((i) => i.label.toLowerCase().contains(query)))
          .map((r) => CabinetTeamMessageReference(
                type: CabinetTeamMessageReferenceType.stockRequest,
                targetId: r.id,
                title: 'Demande de stock · ${r.items.length} '
                    'ligne${r.items.length > 1 ? 's' : ''}',
                subtitle:
                    '${r.pharmacy?.name ?? 'Pharmacie'} · '
                    '${_stockStatusLabel(r.status)}',
              ))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Joindre un objet', style: textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in _kAttachableTypes)
              NubiaChip(
                key: Key('attach_reference_type_${type.name}'),
                label: _typeLabel(type),
                icon: _typeIcon(type),
                variant: NubiaChipVariant.choice,
                selected: _type == type,
                onTap: () => _selectType(type),
              ),
          ],
        ),
        const SizedBox(height: 12),
        NubiaSearchBar(
          key: const Key('attach_reference_search'),
          hint: 'Rechercher…',
          onChanged: _onChanged,
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildResults()),
      ],
    );
  }

  Widget _buildResults() {
    switch (_status) {
      case _Status.loading:
        return const Center(
          key: Key('attach_reference_loading'),
          child: CircularProgressIndicator(),
        );
      case _Status.error:
        return const Text(
          key: Key('attach_reference_error'),
          'Recherche indisponible pour le moment.',
        );
      case _Status.loaded:
        if (_results.isEmpty) {
          return const Text(
            key: Key('attach_reference_empty'),
            'Aucun résultat.',
          );
        }
        return ListView.builder(
          key: const Key('attach_reference_results'),
          itemCount: _results.length,
          itemBuilder: (context, index) {
            final result = _results[index];
            return ListTile(
              key: Key('attach_reference_result_${result.targetId}'),
              leading: Icon(_typeIcon(result.type)),
              title: Text(result.title),
              subtitle: Text(result.subtitle),
              onTap: () => Navigator.of(context).pop(result),
            );
          },
        );
    }
  }
}

String _quoteStatusLabel(CabinetQuoteStatus status) => switch (status) {
      CabinetQuoteStatus.draft => 'Brouillon',
      CabinetQuoteStatus.sent => 'Envoyé',
      CabinetQuoteStatus.signed => 'Signé',
      CabinetQuoteStatus.paid => 'Payé',
      CabinetQuoteStatus.expired => 'Expiré',
      CabinetQuoteStatus.cancelled => 'Annulé',
    };

String _labStatusLabel(String status) => switch (status) {
      'sent' => 'Envoyé',
      'try_in' => 'Essayage',
      'returned' => 'Retourné',
      'fitted' => 'Posé',
      _ => status,
    };

String _stockStatusLabel(StockRequestStatus status) => switch (status) {
      StockRequestStatus.sent => 'Envoyée',
      StockRequestStatus.accepted => 'Acceptée',
      StockRequestStatus.rejected => 'Refusée',
      StockRequestStatus.fulfilled => 'Honorée',
      StockRequestStatus.cancelled => 'Annulée',
    };
