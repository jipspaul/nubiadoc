import 'package:nubia_domain/src/entities/appointment.dart';

import 'cached_data.dart';

abstract class AppointmentsCache {
  Future<CachedData<List<Appointment>>?> getUpcoming();
  Future<CachedData<Appointment>?> getById(String id);
  Future<void> saveUpcoming(List<Appointment> appointments);
  Future<void> saveOne(Appointment appointment);
  Future<void> remove(String id);
  Future<void> clear();
  Future<void> clearUpcoming();
}
