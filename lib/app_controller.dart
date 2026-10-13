import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models/deadline.dart';
import 'services/calendar_repository.dart';
import 'services/notification_service.dart';
import 'services/home_widget_bridge.dart';
import 'services/moodle_api_credentials_store.dart';
import 'services/moodle_api_client.dart';
import 'services/moodle_deadline_merger.dart';

class AppController extends ChangeNotifier {
  AppController(this._repository);

  final CalendarRepository _repository;

  List<Deadline> deadlines = const [];
  List<Deadline> manualDeadlines = const [];
  List<Deadline> apiDeadlines = const [];
  List<String> additionalCalendarUrls = const [];

  List<Deadline> get allDeadlines =>
      [
        ...MoodleDeadlineMerger.merge(deadlines, apiDeadlines),
        ...manualDeadlines,
      ]..sort((a, b) {
        final priority = b.priority.compareTo(a.priority);
        return priority != 0 ? priority : a.due.compareTo(b.due);
      });
  Set<String> completedIds = {};
  List<int> reminderOffsets = const [24, 6, 1];
  Map<String, List<int>> taskReminderOffsets = {};
  DateTime? lastSync;
  bool busy = false;
  bool _syncInProgress = false;
  bool initialized = false;
  bool calendarConnected = false;
  String? error;
  ThemeMode themeMode = ThemeMode.system;
  Locale locale = const Locale('en');

  List<Deadline> get activeDeadlines => allDeadlines
      .where((deadline) => !completedIds.contains(deadline.stableKey))
      .toList();

  List<Deadline> get completedDeadlines => allDeadlines
      .where((deadline) => completedIds.contains(deadline.stableKey))
      .toList();

  Future<void> initialize() async {
    await _repository.migrateLegacyStorage();

    final results = await Future.wait<dynamic>([
      _repository.loadCalendarUrl(),
      _repository.loadCachedDeadlines(),
      _repository.loadReminderOffsets(),
      _repository.loadCompletedIds(),
      _repository.loadLastSync(),
      _repository.loadThemeMode(),
      _repository.loadLocale(),
      _repository.loadTaskReminderOffsets(),
      _repository.loadManualDeadlines(),
      _repository.loadAdditionalCalendarUrls(),
    ]);

    calendarConnected = results[0] != null;
    deadlines = results[1] as List<Deadline>;
    reminderOffsets = results[2] as List<int>;
    completedIds = results[3] as Set<String>;
    lastSync = results[4] as DateTime?;
    themeMode = _parseThemeMode(results[5] as String);
    locale = Locale((results[6] as String) == 'ar' ? 'ar' : 'en');
    taskReminderOffsets = results[7] as Map<String, List<int>>;
    manualDeadlines = results[8] as List<Deadline>;
    additionalCalendarUrls = results[9] as List<String>;
    initialized = true;
    await _publishWidget();
    notifyListeners();

    if (calendarConnected) {
      await NotificationService.init(requestPermissions: true);
      await sync(silent: true);
    }
  }

  Future<bool> connect(String url) async {
    busy = true;
    error = null;
    notifyListeners();

    try {
      await _repository.saveCalendarUrl(url);
      await NotificationService.init(requestPermissions: true);
      calendarConnected = true;
      await _syncInternal();
      return true;
    } catch (exception) {
      error = _message(exception);
      await _repository.clearCalendarUrl();
      calendarConnected = false;
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> sync({bool silent = false}) async {
    if (!calendarConnected || busy || _syncInProgress) return false;
    _syncInProgress = true;
    busy = true;
    error = null;
    notifyListeners();

    try {
      await _syncInternal();
      return true;
    } catch (exception) {
      error = _message(exception);
      return false;
    } finally {
      _syncInProgress = false;
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _syncInternal() async {
    deadlines = await _repository.sync();
    await _syncOptionalApi();
    lastSync = await _repository.loadLastSync();
    error = null;
    await _rescheduleNotifications();
    await _publishWidget();
    notifyListeners();
  }

  Future<void> _syncOptionalApi() async {
    try {
      final store = MoodleApiCredentialsStore(const FlutterSecureStorage());
      final credentials = await store.load();
      if (credentials == null) {
        apiDeadlines = const [];
        return;
      }
      final api = MoodleApiClient(
        baseUrl: credentials.server,
        token: credentials.token,
      );
      try {
        final info = await api.siteInfo();
        final userId = (info['userid'] as num?)?.toInt();
        if (userId == null) return;
        final courses = await api.courses(userId);
        final ids = courses
            .map((course) => (course['id'] as num?)?.toInt())
            .whereType<int>()
            .toList();
        apiDeadlines = await api.assignments(ids);
      } finally {
        api.close();
      }
    } catch (_) {
      // Optional API errors must never prevent iCalendar synchronization.
    }
  }

  Future<void> _publishWidget() async {
    try {
      await HomeWidgetBridge.publish(allDeadlines, completedIds);
    } catch (_) {
      // Platform widgets are optional (for example on iOS and in tests).
    }
  }

  Future<void> addCalendarSource(String url) async {
    await _repository.addAdditionalCalendarUrl(url);
    additionalCalendarUrls = await _repository.loadAdditionalCalendarUrls();
    notifyListeners();
    if (calendarConnected) await sync();
  }

  Future<void> removeCalendarSource(String url) async {
    await _repository.removeAdditionalCalendarUrl(url);
    additionalCalendarUrls = await _repository.loadAdditionalCalendarUrls();
    notifyListeners();
    if (calendarConnected) await sync();
  }

  Future<void> addManualDeadline(Deadline deadline) async {
    manualDeadlines = [...manualDeadlines, deadline];
    await _repository.saveManualDeadlines(manualDeadlines);
    await _rescheduleNotifications();
    notifyListeners();
  }

  Future<void> deleteManualDeadline(Deadline deadline) async {
    manualDeadlines = manualDeadlines
        .where((item) => item.stableKey != deadline.stableKey)
        .toList();
    completedIds.remove(deadline.stableKey);
    taskReminderOffsets.remove(deadline.stableKey);
    await _repository.saveManualDeadlines(manualDeadlines);
    await _repository.saveCompletedIds(completedIds);
    await _repository.saveTaskReminderOffsets(taskReminderOffsets);
    await _rescheduleNotifications();
    notifyListeners();
  }

  Future<void> toggleCompleted(Deadline deadline) async {
    final key = deadline.stableKey;
    if (completedIds.contains(key)) {
      completedIds.remove(key);
    } else {
      completedIds.add(key);
    }
    await _repository.saveCompletedIds(completedIds);
    await _rescheduleNotifications();
    notifyListeners();
  }

  Future<void> setReminderOffsets(List<int> values) async {
    reminderOffsets = values.toSet().toList()..sort((a, b) => b.compareTo(a));
    await _repository.saveReminderOffsets(reminderOffsets);
    await _rescheduleNotifications();
    notifyListeners();
  }

  Future<void> setTaskReminderOffsets(
    Deadline deadline,
    List<int>? offsets,
  ) async {
    final key = deadline.stableKey;
    if (offsets == null) {
      taskReminderOffsets.remove(key);
    } else {
      taskReminderOffsets[key] = offsets.where((h) => h > 0).toSet().toList();
    }
    await _repository.saveTaskReminderOffsets(taskReminderOffsets);
    await _rescheduleNotifications();
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    themeMode = value;
    await _repository.saveThemeMode(value.name);
    notifyListeners();
  }

  Future<void> setLocale(Locale value) async {
    locale = value.languageCode == 'ar'
        ? const Locale('ar')
        : const Locale('en');
    await _repository.saveLocale(locale.languageCode);
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _repository.clearCalendarUrl();
    await _repository.clearCachedCalendarData();
    deadlines = const [];
    completedIds = {};
    taskReminderOffsets = {};
    lastSync = null;
    calendarConnected = false;
    error = null;
    await _rescheduleNotifications();
    notifyListeners();
  }

  Future<void> _rescheduleNotifications() {
    return NotificationService.scheduleAll(
      allDeadlines,
      reminderOffsetsHours: reminderOffsets,
      completedIds: completedIds,
      taskReminderOffsets: taskReminderOffsets,
    );
  }

  ThemeMode _parseThemeMode(String value) {
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ThemeMode.system,
    );
  }

  String _message(Object exception) {
    if (exception is CalendarSyncException) return exception.message;
    return 'Could not sync Moodle. Check your connection and calendar URL.';
  }
}
