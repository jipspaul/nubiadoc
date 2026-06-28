import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:nubia_core/nubia_core.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class OublietteItem extends Equatable {
  final String id;
  final String title;
  final DateTime seenAt;

  const OublietteItem({
    required this.id,
    required this.title,
    required this.seenAt,
  });

  @override
  List<Object?> get props => [id, title, seenAt];
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

sealed class OubliettesEvent extends Equatable {
  const OubliettesEvent();

  @override
  List<Object?> get props => [];
}

final class OubliettesLoadRequested extends OubliettesEvent {
  const OubliettesLoadRequested();
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

sealed class OubliettesState extends Equatable {
  const OubliettesState();

  @override
  List<Object?> get props => [];
}

final class OubliettesInitial extends OubliettesState {
  const OubliettesInitial();
}

final class OubliettesLoading extends OubliettesState {
  const OubliettesLoading();
}

final class OubliettesLoaded extends OubliettesState {
  final List<OublietteItem> items;

  const OubliettesLoaded(this.items);

  @override
  List<Object?> get props => [items];
}

final class OubliettesError extends OubliettesState {
  final String message;

  const OubliettesError(this.message);

  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// BLoC
// ---------------------------------------------------------------------------

class OubliettesBloc extends Bloc<OubliettesEvent, OubliettesState>
    with SafeEmitMixin<OubliettesState> {
  OubliettesBloc() : super(const OubliettesInitial()) {
    on<OubliettesLoadRequested>(_onLoad);
  }

  Future<void> _onLoad(
    OubliettesLoadRequested event,
    Emitter<OubliettesState> emit,
  ) async {
    emit(const OubliettesLoading());
    // Mock local — la route /v1/documents?recent=true viendra plus tard.
    final items = [
      OublietteItem(
        id: '1',
        title: 'Ordonnance Dr Martin',
        seenAt: DateTime(2026, 6, 19),
      ),
      OublietteItem(
        id: '2',
        title: 'Radio panoramique',
        seenAt: DateTime(2026, 6, 18),
      ),
      OublietteItem(
        id: '3',
        title: 'Bilan sanguin',
        seenAt: DateTime(2026, 6, 15),
      ),
    ];
    emit(OubliettesLoaded(items));
  }
}
