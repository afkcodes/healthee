import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/basics/breathing/breathing_pattern.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';
import 'package:healthee/data/basics/breathing/breathing_settings.dart';
import 'package:healthee/data/basics/breathing/breathing_settings_provider.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/store/store_provider.dart';

void main() {
  late LocalStore database;
  late ProviderContainer container;

  ProviderContainer open() => ProviderContainer(
    overrides: [localStoreProvider.overrideWithValue(database)],
  );

  setUp(() {
    database = LocalStore.memory();
    container = open();
  });
  tearDown(() async {
    container.dispose();
    await database.close();
  });

  test('defaults: all four on, free from 22:15, morning fallback 08:00', () {
    const settings = BreathingSettings();
    for (final kind in BreathingItemKind.values) {
      expect(settings.isEnabled(kind), isTrue);
    }
    expect(settings.nightFreeFromMinute, 22 * 60 + 15);
    expect(settings.morningDefaultMinute, 480);
    expect(settings.custom, isNull);
    expect(settings.acceptedAt, isNull);
    expect(BreathingSettings.decode(null).off, isEmpty);
  });

  test('encode and decode round trip', () {
    final settings = BreathingSettings(
      off: const {BreathingItemKind.midday},
      nightFreeFromMinute: 1290,
      morningDefaultMinute: 450,
      custom: BreathPattern.custom(
        inSeconds: 3,
        hold1Seconds: 1,
        outSeconds: 7,
        hold2Seconds: 0,
      ),
      patternOverrides: const {BreathingItemKind.night: 'custom'},
      acceptedAt: DateTime.fromMillisecondsSinceEpoch(1760000000000),
    );
    final back = BreathingSettings.decode(settings.encode());
    expect(back.off, {BreathingItemKind.midday});
    expect(back.nightFreeFromMinute, 1290);
    expect(back.morningDefaultMinute, 450);
    expect(back.custom, settings.custom);
    expect(back.patternOverrides, settings.patternOverrides);
    expect(back.acceptedAt, settings.acceptedAt);
    expect(back.patternFor(BreathingItemKind.night), settings.custom);
    expect(back.patternFor(BreathingItemKind.morning), kSteady);
  });

  test('invalid stored values throw rather than silently defaulting', () {
    expect(() => BreathingSettings.decode('[]'), throwsFormatException);
    expect(
      () => BreathingSettings.decode(
        '{"off":["nope"],"night_free_from":1,"morning_default":1}',
      ),
      throwsFormatException,
    );
    expect(
      () => BreathingSettings.decode(
        '{"night_free_from":2000,"morning_default":1}',
      ),
      throwsFormatException,
    );
  });

  test('choosing custom before setting counts falls back to the default', () {
    const settings = BreathingSettings(
      patternOverrides: {BreathingItemKind.night: 'custom'},
    );
    expect(settings.patternFor(BreathingItemKind.night), kLongExhale);
  });

  test('the controller persists changes across a fresh container', () async {
    final notifier = container.read(
      breathingSettingsControllerProvider.notifier,
    );
    await container.read(breathingSettingsControllerProvider.future);
    await notifier.setEnabled(BreathingItemKind.onDemand, on: false);
    await notifier.setNightFreeFrom(1290);
    await notifier.setCustom(
      inSeconds: 4,
      hold1Seconds: 0,
      outSeconds: 8,
      hold2Seconds: 0,
    );
    await notifier.setPattern(BreathingItemKind.morning, 'custom');
    container.dispose();
    container = open();
    final saved = await container.read(
      breathingSettingsControllerProvider.future,
    );
    expect(saved.isEnabled(BreathingItemKind.onDemand), isFalse);
    expect(saved.nightFreeFromMinute, 1290);
    expect(saved.patternFor(BreathingItemKind.morning).outSeconds, 8);
  });

  test('accept all turns everything on and stamps the time', () async {
    final notifier = container.read(
      breathingSettingsControllerProvider.notifier,
    );
    await container.read(breathingSettingsControllerProvider.future);
    await notifier.setEnabled(BreathingItemKind.midday, on: false);
    await notifier.acceptAll();
    final saved = await container.read(
      breathingSettingsControllerProvider.future,
    );
    expect(saved.off, isEmpty);
    expect(saved.acceptedAt, isNotNull);
  });

  test('bad input is refused, not stored', () async {
    final notifier = container.read(
      breathingSettingsControllerProvider.notifier,
    );
    await container.read(breathingSettingsControllerProvider.future);
    await expectLater(notifier.setNightFreeFrom(1440), throwsFormatException);
    await expectLater(
      notifier.setCustom(
        inSeconds: 0,
        hold1Seconds: 0,
        outSeconds: 5,
        hold2Seconds: 0,
      ),
      throwsFormatException,
    );
    await expectLater(
      notifier.setPattern(BreathingItemKind.night, 'custom'),
      throwsFormatException,
    );
    await expectLater(
      notifier.setPattern(BreathingItemKind.night, 'nope'),
      throwsFormatException,
    );
    final saved = await container.read(
      breathingSettingsControllerProvider.future,
    );
    expect(saved.nightFreeFromMinute, 1335);
  });
}
