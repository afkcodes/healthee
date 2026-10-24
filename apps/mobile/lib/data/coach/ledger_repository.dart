import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/coach/ledger_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ledger_repository.g.dart';

/// The ledger's three windows, named as the server names them.
enum LedgerWindow {
  /// The last seven days.
  week,

  /// The last month.
  month,

  /// Since the coach began.
  all,
}

/// Reads `/api/coach/ledger` through the one account client.
class LedgerRepository {
  /// Reads through [api].
  const LedgerRepository(this.api);

  /// The account's client.
  final AccountApi api;

  /// The ledger over [window].
  Future<CoachLedger> ledger(LedgerWindow window) async => CoachLedger.fromJson(
    await api.get('/api/coach/ledger', query: {'window': window.name}),
  );
}

@riverpod
Future<LedgerRepository> ledgerRepository(Ref ref) async =>
    LedgerRepository(await ref.watch(accountApiProvider.future));

@riverpod
Future<CoachLedger> coachLedger(Ref ref, LedgerWindow window) async {
  final repository = await ref.watch(ledgerRepositoryProvider.future);
  return repository.ledger(window);
}
