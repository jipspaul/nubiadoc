import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:nubia_domain/src/entities/appointment.dart';

import '../../remote/scheduling/appointment_dto.dart';
import '../appointments_cache.dart';
import '../cached_data.dart';
import 'nubia_database.dart';

class DriftAppointmentsCache implements AppointmentsCache {
  final NubiaDatabase _db;

  DriftAppointmentsCache(this._db);

  @override
  Future<CachedData<List<Appointment>>?> getUpcoming() async {
    final tsRows = await _db
        .customSelect(
          "SELECT cached_at FROM cache_timestamps WHERE cache_key = 'upcoming'",
        )
        .get();
    if (tsRows.isEmpty) return null;

    final cachedAt = DateTime.fromMillisecondsSinceEpoch(
        tsRows.first.read<int>('cached_at'));

    final rows = await _db
        .customSelect(
          "SELECT json FROM cached_appointments WHERE list_key = 'upcoming'",
        )
        .get();

    final appointments = rows.map((r) {
      final map = jsonDecode(r.read<String>('json')) as Map<String, dynamic>;
      return AppointmentDto.fromJson(map).toDomain();
    }).toList();

    return CachedData(data: appointments, cachedAt: cachedAt);
  }

  @override
  Future<CachedData<Appointment>?> getById(String id) async {
    final rows = await _db.customSelect(
      "SELECT json, cached_at FROM cached_appointments WHERE id = ? AND list_key = '_single'",
      variables: [Variable.withString(id)],
    ).get();
    if (rows.isEmpty) return null;

    final row = rows.first;
    final cachedAt =
        DateTime.fromMillisecondsSinceEpoch(row.read<int>('cached_at'));
    final map = jsonDecode(row.read<String>('json')) as Map<String, dynamic>;
    final appointment = AppointmentDto.fromJson(map).toDomain();

    return CachedData(data: appointment, cachedAt: cachedAt);
  }

  @override
  Future<void> saveUpcoming(List<Appointment> appointments) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await _db.customStatement(
        "DELETE FROM cached_appointments WHERE list_key = 'upcoming'",
      );
      for (final a in appointments) {
        await _db.customStatement(
          'INSERT OR REPLACE INTO cached_appointments (id, json, list_key, cached_at) VALUES (?, ?, ?, ?)',
          [a.id, jsonEncode(_appointmentToMap(a)), 'upcoming', now],
        );
      }
      await _db.customStatement(
        "INSERT OR REPLACE INTO cache_timestamps (cache_key, cached_at) VALUES ('upcoming', ?)",
        [now],
      );
    });
  }

  @override
  Future<void> saveOne(Appointment appointment) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.customStatement(
      "INSERT OR REPLACE INTO cached_appointments (id, json, list_key, cached_at) VALUES (?, ?, '_single', ?)",
      [appointment.id, jsonEncode(_appointmentToMap(appointment)), now],
    );
  }

  @override
  Future<void> remove(String id) async {
    await _db.customStatement(
      "DELETE FROM cached_appointments WHERE id = ? AND list_key = '_single'",
      [id],
    );
  }

  @override
  Future<void> clearUpcoming() async {
    await _db.transaction(() async {
      await _db.customStatement(
        "DELETE FROM cached_appointments WHERE list_key = 'upcoming'",
      );
      await _db.customStatement(
        "DELETE FROM cache_timestamps WHERE cache_key = 'upcoming'",
      );
    });
  }

  @override
  Future<void> clear() async {
    await _db.customStatement('DELETE FROM cached_appointments');
    await _db.customStatement('DELETE FROM cache_timestamps');
  }

  Map<String, dynamic> _appointmentToMap(Appointment a) => {
        'id': a.id,
        'cabinet_id': a.cabinetId,
        'practitioner_name': a.practitionerName,
        'practitioner_specialty': a.practitionerSpecialty,
        'starts_at': a.startsAt.toIso8601String(),
        'duration_minutes': a.duration.inMinutes,
        'motif': a.motif,
        'status': a.status.name == 'noShow' ? 'no_show' : a.status.name,
        'type':
            a.type == AppointmentType.teleconsult ? 'teleconsult' : 'in_person',
        'cabinet_address': a.cabinetAddress,
        'cabinet_phone': a.cabinetPhone,
      };
}
