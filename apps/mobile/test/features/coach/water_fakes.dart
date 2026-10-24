/// A host and a fake server for the water card tests. **Not a test.**
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/api/cache_session.dart';
import 'package:healthee/data/api/server_snapshot.dart';
import 'package:healthee/data/basics/water/water_controller.dart';
import 'package:healthee/data/journal/journal_entry.dart';
import 'package:healthee/data/journal/journal_feed.dart';
import 'package:healthee/data/journal/journal_repository.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/features/coach/v02/water_card.dart';

/// The owner's day in these tests.
final DateTime kWaterNow = DateTime(2026, 10, 19, 15);

/// A water entry on the owner's day.
JournalEntry waterEntry(String id, int hour, int minute, [double ml = 250]) =>
    JournalEntry(
      type: 'water',
      at: DateTime(2026, 10, 19, hour, minute).toUtc(),
      amount: ml,
      unit: 'ml',
      id: id,
    );

/// A fake server: holds entries, records every request, can fail on cue.
class FakeWaterServer {
  FakeWaterServer(this.entries);

  /// What the feed returns.
  List<JournalEntry> entries;

  /// Every request as `METHOD path`.
  final List<String> requests = [];

  /// Bodies of POSTs.
  final List<Object?> posted = [];

  /// Fail writes with a connection error.
  bool failWrites = false;

  /// Answer DELETE with 404.
  bool deleteMissing = false;

  /// Fail the feed read.
  bool failFeed = false;

  /// Never answer the feed (loading).
  bool feedNever = false;

  /// How many times the feed was read.
  int feedReads = 0;

  Dio dio() {
    final dio = Dio(BaseOptions(baseUrl: 'https://test.example'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          requests.add('${request.method} ${request.path}');
          if (request.method == 'POST') posted.add(request.data);
          if (failWrites) {
            handler.reject(
              DioException.connectionError(
                requestOptions: request,
                reason: 'offline',
              ),
            );
          } else if (request.method == 'DELETE' && deleteMissing) {
            handler.reject(
              DioException.badResponse(
                statusCode: 404,
                requestOptions: request,
                response: Response(requestOptions: request, statusCode: 404),
              ),
            );
          } else {
            handler.resolve(
              Response(
                requestOptions: request,
                data: <String, Object?>{'ok': true},
              ),
            );
          }
        },
      ),
    );
    return dio;
  }
}

/// The card alone, over [server] and [store].
Widget waterHost(
  FakeWaterServer server,
  LocalStore store, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => ProviderScope(
  overrides: [
    localStoreProvider.overrideWithValue(store),
    waterClockProvider.overrideWithValue(() => kWaterNow),
    journalRepositoryProvider.overrideWith(
      (ref) async =>
          JournalRepository(server.dio(), await CacheSession.capture(null)),
    ),
    journalFeedProvider.overrideWith((ref) async* {
      server.feedReads++;
      if (server.feedNever) {
        await Completer<void>().future;
      }
      if (server.failFeed) throw StateError('feed down');
      yield ServerSnapshot(
        JournalFeed(entries: List.of(server.entries), fastOpen: false),
        fetchedAt: DateTime.now(),
      );
    }),
  ],
  child: MaterialApp(
    theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: const Scaffold(
      body: SingleChildScrollView(
        child: Padding(padding: EdgeInsets.all(20), child: WaterCard()),
      ),
    ),
  ),
);
