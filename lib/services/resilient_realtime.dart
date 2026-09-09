import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Realtime helper for GG Messenger.
///
/// It deliberately does not make Realtime the source of truth. The database
/// query is always used as the initial/fallback load, while Realtime is used
/// for live changes when available.
class ResilientRealtime {
  ResilientRealtime(this.client);

  final SupabaseClient client;

  /// Returns a stream that first loads the current rows from PostgREST and
  /// then listens for Realtime changes. If Realtime times out/disconnects,
  /// the last database snapshot remains available and the stream retries.
  Stream<List<Map<String, dynamic>>> table({
    required String table,
    required List<String> primaryKey,
    String? filterColumn,
    Object? filterValue,
    String? orderColumn,
    bool ascending = true,
    Duration retryDelay = const Duration(seconds: 4),
  }) async* {
    while (true) {
      try {
        var query = client.from(table).select();
        if (filterColumn != null && filterValue != null) {
          query = query.eq(filterColumn, filterValue);
        }

        final initial = await query.order(orderColumn ?? 'created_at', ascending: ascending);
        yield List<Map<String, dynamic>>.from(initial);

        final streamQuery = client.from(table).stream(primaryKey: primaryKey);
        final filtered = filterColumn != null && filterValue != null
            ? streamQuery.eq(filterColumn, filterValue)
            : streamQuery;
        final realtime = filtered.order(orderColumn ?? 'created_at', ascending: ascending);

        await for (final rows in realtime) {
          yield List<Map<String, dynamic>>.from(rows);
        }
      } catch (_) {
        // Keep the database as the fallback and reconnect quietly.
        await Future<void>.delayed(retryDelay);
      }
    }
  }
}
