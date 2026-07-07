import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'bookable_slots_event.dart';
import 'bookable_slots_state.dart';

/// Nettoie la liste de créneaux avant affichage (issue #3365).
///
/// Les données de seed contiennent des créneaux périmés et des doublons. Côté
/// front on :
/// - masque les créneaux **passés** (`endsAt` avant/à [now]) ;
/// - déduplique par praticien + plage horaire, en gardant de préférence le
///   créneau **disponible** ;
/// - trie par date de début croissante pour un affichage stable.
List<Slot> sanitizeBookableSlots(List<Slot> slots, DateTime now) {
  final byKey = <String, Slot>{};
  for (final slot in slots) {
    if (!slot.endsAt.isAfter(now)) continue; // créneau passé → masqué
    final key = '${slot.practitionerId}|'
        '${slot.startsAt.toIso8601String()}|'
        '${slot.endsAt.toIso8601String()}';
    final existing = byKey[key];
    // Doublon : on privilégie le créneau disponible sur l'indisponible.
    if (existing == null || (!existing.isAvailable && slot.isAvailable)) {
      byKey[key] = slot;
    }
  }
  final result = byKey.values.toList()
    ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  return result;
}

class BookableSlotsBloc extends Bloc<BookableSlotsEvent, BookableSlotsState>
    with SafeEmitMixin<BookableSlotsState> {
  final ListBookableSlotsUseCase _listSlots;
  final CreateSlotUseCase _createSlot;
  final ListCabinetPractitionersUseCase _listPractitioners;
  final DateTime Function() _now;

  BookableSlotsBloc({
    required ListBookableSlotsUseCase listSlots,
    required CreateSlotUseCase createSlot,
    required ListCabinetPractitionersUseCase listPractitioners,
    DateTime Function()? now,
  })  : _listSlots = listSlots,
        _createSlot = createSlot,
        _listPractitioners = listPractitioners,
        _now = now ?? DateTime.now,
        super(const BookableSlotsInitial()) {
    on<BookableSlotsLoadRequested>(_onLoad);
    on<CreateSlotRequested>(_onCreate);
  }

  Future<void> _onLoad(
    BookableSlotsLoadRequested event,
    Emitter<BookableSlotsState> emit,
  ) async {
    emit(const BookableSlotsLoading());
    try {
      // #3365 : ne pas charger les créneaux passés — l'API filtre via `from`
      // (sanitizeBookableSlots reste en défense côté client).
      // #3467 : on charge aussi le roster praticiens pour afficher le nom du
      // médecin sur chaque créneau et alimenter les sélecteurs.
      final slotsResult = await _listSlots(from: _now());
      final failure = slotsResult.fold((f) => f, (_) => null);
      if (failure != null) {
        safeEmit(BookableSlotsError(failure.message));
        return;
      }
      final slots = slotsResult.getOrElse(() => const []);
      // Le roster est secondaire : en cas d'échec, on affiche quand même les
      // créneaux (sans nom de praticien) plutôt que de bloquer l'écran.
      final practitionersResult = await _listPractitioners();
      final practitioners = practitionersResult.getOrElse(() => const []);
      safeEmit(BookableSlotsLoaded(
        sanitizeBookableSlots(slots, _now()),
        practitioners: practitioners,
      ));
    } catch (_) {
      safeEmit(const BookableSlotsError('Erreur de chargement.'));
    }
  }

  Future<void> _onCreate(
    CreateSlotRequested event,
    Emitter<BookableSlotsState> emit,
  ) async {
    emit(const BookableSlotsLoading());
    try {
      final result = await _createSlot(
        // `cabinet_id` est ignoré par le back (extrait du JWT) ; seul le
        // `practitioner_id` valide compte (#3465).
        cabinetId: '',
        practitionerId: event.practitionerId,
        start: event.startsAt,
        duration: event.endsAt.difference(event.startsAt),
      );
      result.fold(
        (failure) => safeEmit(BookableSlotsError(failure.message)),
        (_) {
          safeEmit(const BookableSlotsSlotCreatedSuccess());
          add(const BookableSlotsLoadRequested());
        },
      );
    } catch (_) {
      safeEmit(const BookableSlotsError('Erreur de chargement.'));
    }
  }
}
