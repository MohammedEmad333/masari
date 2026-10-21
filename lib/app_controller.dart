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
  List<Deadline> sessionDeadlines = const [];
  List<String> additionalCalendarUrls = const [];

  List<Deadline> get allDeadlines =>
      [
        ...MoodleDeadlineMerger.merge(deadlines, apiDeadlines),
        ...sessionDeadlines,
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
  bool apiConnected = false;
  bool offlineMode = false;
  bool get hasConnection =>
      calendarConnected ||
      apiConnected ||
      sessionDeadlines.isNotEmpty ||
      manualDeadlines.isNotEmpty ||
      offlineMode;
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
      _repository.loadCachedApiDeadlines(),
      _repository.loadSessionDeadlines(),
      _repository.loadOfflineMode(),
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
    apiDeadlines = results[10] as List<Deadline>;
    sessionDeadlines = results[11] as List<Deadline>;
    offlineMode = results[12] as bool;
    apiConnected = await _hasApiCredentials();
    initialized = true;
    await _publishWidget();
    notifyListeners();

    if (calendarConnected ||
        apiConnected ||
        sessionDeadlines.isNotEmpty ||
        manualDeadlines.isNotEmpty) {
      await NotificationService.init(requestPermissions: true);
      if (calendarConnected || apiConnected) {
        // A failed network refresh must not discard reminders restored from
        // persisted manual, API and session deadline caches.
        if (!await sync(silent: true)) await _rescheduleNotifications();
      } else {
        // Manual-only and session-only users still need restored reminders.
        await _rescheduleNotifications();
      }
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
    if (!(calendarConnected || apiConnected) || busy || _syncInProgress) {
      return false;
    }
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
    if (calendarConnected) {
      deadlines = await _repository.sync();
    }
    final apiSucceeded = await _syncOptionalApi();
    if (!calendarConnected && !apiSucceeded) {
      throw const CalendarSyncException(
        'Could not sync Moodle API. Check your connection.',
      );
    }
    lastSync = calendarConnected
        ? await _repository.loadLastSync()
        : DateTime.now();
    error = null;
    await _rescheduleNotifications();
    await _publishWidget();
    notifyListeners();
  }

  Future<bool> _hasApiCredentials() async {
    final store = MoodleApiCredentialsStore(const FlutterSecureStorage());
    return await store.load() != null;
  }

  Future<void> refreshApiConnection() async {
    apiConnected = await _hasApiCredentials();
    if (!apiConnected) {
      apiDeadlines = const [];
      await _repository.clearCachedApiDeadlines();
    }
    if (apiConnected) await NotificationService.init(requestPermissions: true);
    await _rescheduleNotifications();
    await _publishWidget();
    notifyListeners();
  }

  Future<bool> _syncOptionalApi() async {
    try {
      final store = MoodleApiCredentialsStore(const FlutterSecureStorage());
      final credentials = await store.load();
      apiConnected = credentials != null;
      if (credentials == null) {
        apiDeadlines = const [];
        await _repository.clearCachedApiDeadlines();
        return false;
      }
      final api = MoodleApiClient(
        baseUrl: credentials.server,
        token: credentials.token,
      );
      try {
        final info = await api.siteInfo();
        final userId = (info['userid'] as num?)?.toInt();
        if (userId == null) return false;
        final courses = await api.courses(userId);
        final ids = courses
            .map((course) => (course['id'] as num?)?.toInt())
            .whereType<int>()
            .toList();
        final fetched = await api.assignments(ids);
        await _repository.saveCachedApiDeadlines(fetched);
        apiDeadlines = fetched;
        return true;
      } finally {
        api.close();
      }
    } catch (_) {
      // Preserve cached API tasks and keep iCalendar independent.
      return false;
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

  /// One-time manual import; session cookies and university credentials
  /// never leave the embedded browser or enter persistent storage.
  Future<void> importSessionDeadlines(List<Deadline> values) async {
    sessionDeadlines = values;
    await _repository.saveSessionDeadlines(values);
    await NotificationService.init(requestPermissions: true);
    await _rescheduleNotifications();
    await _publishWidget();
    notifyListeners();
  }

  Future<void> clearImportedSessionDeadlines() async {
    sessionDeadlines = const [];
    await _repository.clearSessionDeadlines();
    await _rescheduleNotifications();
    await _publishWidget();
    notifyListeners();
  }

  Future<void> addManualDeadline(Deadline deadline) async {
    manualDeadlines = [...manualDeadlines, deadline];
    await _repository.saveManualDeadlines(manualDeadlines);
    // A manual-only user never visits calendar/API onboarding; request Android
    // notification permissions before the first scheduled alert.
    await NotificationService.init(requestPermissions: true);
    await _rescheduleNotifications();
    await _publishWidget();
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
    await _publishWidget();
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
    await _publishWidget();
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

  Future<void> enableOfflineMode() async {
    await _repository.saveOfflineMode(true);
    offlineMode = true;
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
    await _publishWidget();
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
