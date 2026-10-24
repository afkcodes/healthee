import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/basics/breathing/breathing_done.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/store/store_provider.dart';

void main() {
  late LocalStore store;
  var clock = DateTime(2026, 10, 19, 9);
  setUp(() {
    store = LocalStore.memory();
    clock = DateTime(2026, 10, 19, 9);
  });
  tearDown(() => store.close());

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        breathingClockProvider.overrideWithValue(() => clock),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('nothing is done before a session', () async {
    expect(await container().read(breathingDoneProvider.future), isEmpty);
  });

  test('marking is kept for the day and survives a new container', () async {
    final first = container();
    await first.read(breathingDoneProvider.future);
    await first
        .read(breathingDoneProvider.notifier)
        .mark(BreathingItemKind.morning);
    expect(first.read(breathingDoneProvider).value, {
      BreathingItemKind.morning,
    });
    expect(await container().read(breathingDoneProvider.future), {
      BreathingItemKind.morning,
    });
  });

  test('yesterday does not count today', () async {
    final first = container();
    await first.read(breathingDoneProvider.future);
    await first
        .read(breathingDoneProvider.notifier)
        .mark(BreathingItemKind.night);
    clock = DateTime(2026, 10, 20, 8);
    expect(await container().read(breathingDoneProvider.future), isEmpty);
  });

  test('a damaged record is refused, not read as nothing done', () {
    expect(() => BreathingDone.decode('[]'), throwsFormatException);
    expect(
      () => BreathingDone.decode('{"day":"2026-10-19","items":["lunch"]}'),
      throwsFormatException,
    );
  });
}
