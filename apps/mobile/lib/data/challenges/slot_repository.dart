import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/challenges/challenge.dart';

/// Edits the one thing "Change time" may edit: a job's slot.
///
/// `PATCH /api/challenges/{id}/slot` with `{"slot": "<text>"}`. Nothing else
/// about the job moves, so this is the only place the app writes a slot.
class SlotRepository {
  /// Writes through [api].
  const SlotRepository(this.api);

  /// The account's client.
  final AccountApi api;

  /// Sets challenge [id]'s slot to [slot], for example `at 7:30 pm`.
  ///
  /// The server answers `{ok, challenge}`; a 409 means the job is no longer
  /// running and a 404 that it is not this owner's, both thrown as the client
  /// throws them. Returns the challenge as the server now holds it.
  Future<Challenge> setSlot(int id, String slot) async {
    final response = await api.request(
      '/api/challenges/$id/slot',
      method: 'PATCH',
      body: <String, Object?>{'slot': slot},
    );
    final challenge = response['challenge'];
    if (response['ok'] == false || challenge is! Map<String, Object?>) {
      throw const FormatException('Server declined the change');
    }
    return Challenge.fromJson(challenge);
  }
}

/// The repository on the signed-in account.
final FutureProvider<SlotRepository> slotRepositoryProvider =
    FutureProvider<SlotRepository>(
      (ref) async => SlotRepository(await ref.watch(accountApiProvider.future)),
    );
