import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void callServiceEntry() {
  FlutterForegroundTask.setTaskHandler(_CallTaskHandler());
}

// الخدمة بس بتخلي أندرويد يسيب المكالمة شغالة، مفيش شغل بيتعمل جواها
class _CallTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class CallForeground {
  static bool _inited = false;

  static void _init() {
    if (_inited) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'wanas_call',
        channelName: 'مكالمات ونس',
        channelDescription: 'إشعار المكالمة الجارية',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _inited = true;
  }

  static Future<void> start(String name) async {
    try {
      _init();
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.startService(
        serviceId: 4201,
        notificationTitle: 'مكالمة جارية',
        notificationText: 'مع $name، اضغط للرجوع للمكالمة',
        callback: callServiceEntry,
      );
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }
}