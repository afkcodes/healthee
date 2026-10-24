import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/background/background_store.dart';
import 'package:healthee/data/basics/breathing/breathing_history.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';
import 'package:healthee/data/basics/breathing/breathing_plan_builder.dart';
import 'package:healthee/data/basics/breathing/breathing_settings.dart';
import 'package:healthee/data/notifications/notification_service.dart';
import 'package:healthee/data/store/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore database;
  late BackgroundStore store;
  late _Plugin plugin;
  late NotificationService service;
  final now = DateTime(2026, 10, 18, 9);

  BreathingPlan plan({
    BreathingSettings settings = const BreathingSettings(),
    bool withStress = true,
  }) => buildBreathingPlan(
    now: now,
    history: BreathingHistory(
      stress: withStress
          ? [StressSample(DateTime(2026, 10, 17, 4), 40)]
          : const [],
    ),
    settings: settings,
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (_) async => 'Asia/Kolkata',
        );
    database = LocalStore.memory();
    store = BackgroundStore(database);
    plugin = _Plugin();
    service = NotificationService(plugin, store);
  });
  tearDown(() async {
    await service.destinations.close();
    await database.close();
  });

  test(
    'schedules 1004 to 1006 daily, payload breathing, none for on demand',
    () async {
      await service.syncBreathingReminders(plan());
      expect(plugin.scheduled.map((s) => s.id), [1004, 1005, 1006]);
      expect(plugin.scheduled.every((s) => s.payload == 'breathing'), isTrue);
      expect(plugin.scheduled.every((s) => s.daily), isTrue);
      expect(plugin.permissionAsked, 1);
    },
  );

  test('a toggle that is off is cancelled and not scheduled', () async {
    await service.syncBreathingReminders(
      plan(settings: const BreathingSettings(off: {BreathingItemKind.midday})),
    );
    expect(plugin.scheduled.map((s) => s.id), [1004, 1006]);
    expect(plugin.cancelledIds, containsAll([1004, 1005, 1006]));
  });

  test('everything off cancels all three and asks no permission', () async {
    await service.syncBreathingReminders(
      plan(
        settings: const BreathingSettings(
          off: {
            BreathingItemKind.morning,
            BreathingItemKind.midday,
            BreathingItemKind.night,
          },
        ),
      ),
    );
    expect(plugin.scheduled, isEmpty);
    expect(plugin.cancelledIds, [1004, 1005, 1006]);
    expect(plugin.permissionAsked, 0);
  });

  test('a refused permission surfaces and schedules nothing', () async {
    plugin.allow = false;
    await expectLater(
      service.syncBreathingReminders(plan()),
      throwsFormatException,
    );
    expect(plugin.scheduled, isEmpty);
  });

  test(
    'restore re-applies saved breathing reminders after a clear-all',
    () async {
      await service.syncBreathingReminders(plan());
      plugin.scheduled.clear();
      await service.restore('scope');
      expect(plugin.scheduled.map((s) => s.id), [1004, 1005, 1006]);
      plugin.scheduled.clear();
      await service.restore(null);
      expect(plugin.scheduled, isEmpty);
    },
  );

  test('the breathing payload is a recognised destination', () async {
    plugin.launch = const NotificationAppLaunchDetails(
      true,
      notificationResponse: NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: 'breathing',
      ),
    );
    final destination = service.destinations.stream.first;
    await service.initialize();
    expect(await destination, 'breathing');
  });
}

class _Scheduled {
  _Scheduled(this.id, this.payload, {required this.daily});
  final int id;
  final String? payload;
  final bool daily;
}

class _Plugin implements FlutterLocalNotificationsPlugin {
  final scheduled = <_Scheduled>[];
  final cancelledIds = <int>[];
  int permissionAsked = 0;
  bool allow = true;
  NotificationAppLaunchDetails? launch;

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async => true;

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => launch;

  @override
  T? resolvePlatformSpecificImplementation<
    T extends FlutterLocalNotificationsPlatform
  >() {
    if (T == AndroidFlutterLocalNotificationsPlugin) {
      return _Android(this) as T;
    }
    return null;
  }

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> cancel({required int id, String? tag}) async =>
      cancelledIds.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #zonedSchedule) {
      scheduled.add(
        _Scheduled(
          invocation.namedArguments[#id]! as int,
          invocation.namedArguments[#payload] as String?,
          daily:
              invocation.namedArguments[#matchDateTimeComponents] ==
              DateTimeComponents.time,
        ),
      );
    }
    return Future<void>.value();
  }
}

class _Android implements AndroidFlutterLocalNotificationsPlugin {
  _Android(this.owner);
  final _Plugin owner;
  @override
  Future<bool?> requestNotificationsPermission() async {
    owner.permissionAsked++;
    return owner.allow;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
