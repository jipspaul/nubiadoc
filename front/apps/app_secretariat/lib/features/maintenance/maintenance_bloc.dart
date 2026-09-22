import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'maintenance_event.dart';
import 'maintenance_state.dart';

/// Écran « Maintenance » du cabinet (#7166/#7167, DP-F18) : compteurs,
/// inventaire d'équipements, tickets — création avec photo (caméra).
class MaintenanceBloc extends Bloc<MaintenanceEvent, MaintenanceState>
    with SafeEmitMixin<MaintenanceState> {
  MaintenanceBloc({
    required GetMaintenanceStatsUseCase getStats,
    required ListEquipmentUseCase listEquipment,
    required ListMaintenanceTicketsUseCase listTickets,
    required CreateMaintenanceTicketUseCase createTicket,
    required UploadMaintenancePhotoUseCase uploadPhoto,
  })  : _getStats = getStats,
        _listEquipment = listEquipment,
        _listTickets = listTickets,
        _createTicket = createTicket,
        _uploadPhoto = uploadPhoto,
        super(const MaintenanceLoading()) {
    on<MaintenanceLoadRequested>(_onLoad);
    on<MaintenanceTicketCreateRequested>(_onCreateTicket);
  }

  final GetMaintenanceStatsUseCase _getStats;
  final ListEquipmentUseCase _listEquipment;
  final ListMaintenanceTicketsUseCase _listTickets;
  final CreateMaintenanceTicketUseCase _createTicket;
  final UploadMaintenancePhotoUseCase _uploadPhoto;

  Future<void> _onLoad(
    MaintenanceLoadRequested event,
    Emitter<MaintenanceState> emit,
  ) async {
    emit(const MaintenanceLoading());
    // Les 3 appels démarrent avant le premier `await` — exécution
    // concurrente malgré des types de retour hétérogènes (`Future.wait` sur
    // une liste mixte `Either<Failure, MaintenanceStats>` /
    // `Either<Failure, List<Equipment>>` / ... ne s'unifie pas proprement).
    final statsFuture = _getStats();
    final equipmentFuture = _listEquipment();
    final ticketsFuture = _listTickets();
    final statsResult = await statsFuture;
    final equipmentResult = await equipmentFuture;
    final ticketsResult = await ticketsFuture;

    final failedMessage = statsResult.fold((f) => f.message, (_) => null) ??
        equipmentResult.fold((f) => f.message, (_) => null) ??
        ticketsResult.fold((f) => f.message, (_) => null);
    if (failedMessage != null) {
      safeEmit(MaintenanceError(failedMessage));
      return;
    }

    safeEmit(MaintenanceLoaded(
      stats: statsResult.getOrElse(() => const MaintenanceStats(
          openTickets: 0, plannedChecks: 0, overdueChecks: 0)),
      equipment: equipmentResult.getOrElse(() => const []),
      tickets: ticketsResult.getOrElse(() => const []),
    ));
  }

  Future<void> _onCreateTicket(
    MaintenanceTicketCreateRequested event,
    Emitter<MaintenanceState> emit,
  ) async {
    final current = state;
    if (current is! MaintenanceLoaded || current.creating) return;

    emit(current.copyWith(creating: true, createError: null));

    final photoDocumentIds = <String>[];
    final photo = event.photo;
    if (photo != null) {
      final uploadResult = await _uploadPhoto(
        bytes: photo.bytes,
        filename: photo.name,
        mimeType: photo.mimeType,
      );
      final uploadFailureMessage =
          uploadResult.fold((failure) => failure.message, (_) => null);
      if (uploadFailureMessage != null) {
        safeEmit(current.copyWith(
          creating: false,
          createError: uploadFailureMessage,
        ));
        return;
      }
      photoDocumentIds
          .add(uploadResult.fold((_) => '', (documentId) => documentId));
    }

    final result = await _createTicket(
      equipmentId: event.equipmentId,
      title: event.title,
      description: event.description,
      priority: event.priority,
      assignedToEmail: event.assignedToEmail,
      photoDocumentIds: photoDocumentIds,
    );
    result.fold(
      (failure) => safeEmit(current.copyWith(
        creating: false,
        createError: failure.message,
      )),
      (ticket) => safeEmit(current.copyWith(
        stats: MaintenanceStats(
          openTickets: current.stats.openTickets + 1,
          plannedChecks: current.stats.plannedChecks,
          overdueChecks: current.stats.overdueChecks,
        ),
        tickets: [ticket, ...current.tickets],
        creating: false,
      )),
    );
  }
}
