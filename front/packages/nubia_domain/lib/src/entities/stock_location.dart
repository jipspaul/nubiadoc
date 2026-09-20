import 'package:equatable/equatable.dart';

/// Une localisation de stock du cabinet (salle…), #7182/#7183. Source :
/// `GET /v1/cabinet/stock-locations`.
class StockLocation extends Equatable {
  final String id;
  final String name;
  final bool isMain;

  const StockLocation({
    required this.id,
    required this.name,
    required this.isMain,
  });

  @override
  List<Object?> get props => [id, name, isMain];
}
