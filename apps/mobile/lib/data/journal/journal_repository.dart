import 'package:dio/dio.dart';
import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/api/cache_session.dart';
import 'package:healthee/data/api/cached_account_read.dart';
import 'package:healthee/data/api/server_snapshot.dart';
import 'package:healthee/data/journal/journal_feed.dart';
import 'package:healthee/data/journal/log_draft.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'journal_repository.g.dart';

/// Binds the editor and all its operations to one account at opening time.
class JournalRepository {
  JournalRepository(Dio dio, CacheSession session)
    : _api = AccountApi(dio, session);
  const JournalRepository.withApi(this._api);
  final AccountApi _api;

  Future<JournalFeed> recent() async => JournalFeed.fromJson(
    await _api.get('/api/log/recent', query: {'days': 7}),
  );

  Future<String?> save(LogDraft draft) async {
    final problem = draft.validate(DateTime.now());
    if (problem != null) throw FormatException(problem);
    return _write(draft.toJson());
  }

  /// Removes the entry [id]. A 404 (already gone) surfaces as the Dio error.
  Future<void> delete(String id) async {
    final result = await _api.request(
      '/api/log/${Uri.encodeComponent(id)}',
      method: 'DELETE',
    );
    if (result['ok'] != true) {
      throw const FormatException('The server did not remove this entry.');
    }
  }

  Future<String?> fasting({required bool end}) =>
      _write({'type': end ? 'fast_end' : 'fast_start'});

  Future<String?> _write(Map<String, Object?> body) async {
    final result = await _api.request('/api/log', method: 'POST', body: body);
    if (result['ok'] != true) {
      throw const FormatException('The server did not accept this entry.');
    }
    return result['discarded'] as String?;
  }
}

@riverpod
Future<JournalRepository> journalRepository(Ref ref) async =>
    JournalRepository.withApi(await ref.watch(accountApiProvider.future));

@riverpod
Stream<ServerSnapshot<JournalFeed>> journalFeed(Ref ref) async* {
  final repository = await ref.watch(journalRepositoryProvider.future);
  yield* cachedAccountRead(
    api: repository._api,
    store: ref.watch(localStoreProvider),
    path: '/api/log/recent',
    key: 'journal_feed',
    parse: JournalFeed.fromJson,
  );
}
