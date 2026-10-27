import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models/deadline.dart';
import 'services/calendar_repository.dart';
import 'services/notification_service.dart';
import 'services/home_widget_bridge.dart';
import 'services/moodle_api_credentials_store.dart';
import 'services/moodle_api_client.dart';
import 'services/deadline_collection.dart';

enum ReminderRepairFailure {
  permissionDenied,
  initializationFailed,
  permissionCheckFailed,
  schedulingFailed,
}

class AppController extends ChangeNotifier {
  AppController(
    this._repository, {
    Future<void> Function()? reminderScheduler,
    Future<void> Function()? notificationInitializer,
    Future<bool?> Function()? notificationPermissionChecker,
  }) : _reminderScheduler = reminderScheduler,
       _notificationInitializer = notificationInitializer,
       _notificationPermissionChecker = notificationPermissionChecker;

  final CalendarRepository _repository;
  final Future<void> Function()? _reminderScheduler;
  final Future<void> Function()? _notificationInitializer;
  final Future<bool?> Function()? _notificationPermissionChecker;
  ReminderRepairFailure? reminderRepairFailure;
  String? get syncWarning => _repository.lastSyncWarning;
  bool reminderSchedulingFailed = false;

  List<Deadline> deadlines = const [];
  List<Deadline> manualDeadlines = const [];
  List<Deadline> apiDeadlines = const [];
  List<Deadline> sessionDeadlines = const [];
  List<String> additionalCalendarUrls = const [];
  Map<String, String> calendarLabels = {};

  List<Deadline> get allDeadlines => DeadlineCollection.combine(
    calendar: deadlines,
    api: apiDeadlines,
    session: sessionDeadlines,
    manual: manualDeadlines,
  );
  Set<String> completedIds = {};
  List<int> reminderOffsets = const [24, 6, 1];
  Map<String, List<int>> taskReminderOffsets = {};
  DateTime? lastSync;
  bool busy = false;
  bool _syncInProgress = false;
  bool initialized = false;
  String? startupError;

  void reportStartupError() {
    initialized = false;
    startupError = 'Unable to load saved data';
    notifyListeners();
  }

  void clearStartupError() {
    startupError = null;
    initialized = false;
    notifyListeners();
  }

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
      _repository.loadCalendarLabels(),
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
    calendarLabels = results[13] as Map<String, String>;
    apiConnected = await _hasApiCredentials();
    initialized = true;
    await _publishWidget();
    notifyListeners();

    if (calendarConnected ||
        apiConnected ||
        sessionDeadlines.isNotEmpty ||
        manualDeadlines.isNotEmpty) {
      try {
        await NotificationService.init(requestPermissions: true);
        if (calendarConnected || apiConnected) {
          // Keep reminders from cached sources when network sync fails.
          if (!await sync(silent: true)) await _rescheduleNotifications();
        } else {
          await _rescheduleNotifications();
        }
      } catch (exception) {
        // Android reminder permissions and scheduling are optional.
        debugPrint('Could not initialize reminders: $exception');
      }
    }
  }

  /// Validate and download the new feed before replacing the stored token or
  /// cached deadlines. An invalid URL must leave the previous calendar intact.
  Future<bool> updateCalendarUrl(String url) async {
    if (busy) return false;
    busy = true;
    error = null;
    reminderSchedulingFailed = false;
    notifyListeners();

    try {
      final updated = await _repository.sync(
        calendarUrl: url,
        additionalCalendarUrls: additionalCalendarUrls,
      );
      deadlines = updated;
      calendarConnected = true;
      lastSync = await _repository.loadLastSync();
      try {
        await NotificationService.init(requestPermissions: true);
        await _rescheduleNotifications();
      } catch (_) {
        reminderSchedulingFailed = true;
        debugPrint('Calendar saved; Android reminders need attention.');
      }
      await _publishWidget();
      notifyListeners();
      return true;
    } catch (exception) {
      error = _message(exception);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> connect(String url) => updateCalendarUrl(url);

  /// The complete URL contains a private token. Read it only after an
  /// explicit user action (editing the connected feed).
  Future<String?> calendarUrlForEditing() => _repository.loadCalendarUrl();

  Future<bool> sync({bool silent = false}) async {
    if (!(calendarConnected || apiConnected) || busy || _syncInProgress) {
      return false;
    }
    _syncInProgress = true;
    busy = true;
    error = null;
    reminderSchedulingFailed = false;
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
    try {
      await _rescheduleNotifications();
    } catch (_) {
      // Downloading/saving Moodle data succeeded; Android notification
      // scheduling is a separate operation and must not mark sync as failed.
      reminderSchedulingFailed = true;
      debugPrint('Calendar synced; Android reminders need attention.');
    }
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
      await HomeWidgetBridge.publish(
        allDeadlines,
        completedIds,
        languageCode: locale.languageCode,
      );
    } catch (_) {
      // Platform widgets are optional (for example on iOS and in tests).
    }
  }

  Future<void> addCalendarSource(String url) async {
    if (!calendarConnected) {
      // An offline-only user has no primary feed yet. Connect the first one
      // rather than saving an additional URL that would never be synced.
      if (!await connect(url)) {
        throw CalendarSyncException(
          error ?? 'Could not connect the first Moodle calendar.',
        );
      }
      return;
    }
    await _repository.addAdditionalCalendarUrl(url);
    additionalCalendarUrls = await _repository.loadAdditionalCalendarUrls();
    notifyListeners();
    if (calendarConnected) await sync();
  }

  Future<void> renameCalendarSource(String url, String name) async {
    await _repository.saveCalendarLabel(url, name);
    calendarLabels = await _repository.loadCalendarLabels();
    notifyListeners();
  }

  Future<void> removeCalendarSource(String url) async {
    await _repository.removeAdditionalCalendarUrl(url);
    additionalCalendarUrls = await _repository.loadAdditionalCalendarUrls();
    calendarLabels = await _repository.loadCalendarLabels();
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

  Future<void> addManualDeadline(Deadline deadline) {
    return saveManualDeadline(deadline);
  }

  /// Persist first: a notification scheduling failure must never create a
  /// duplicate task when a user retries saving the same dialog.
  Future<void> saveManualDeadline(Deadline deadline) async {
    final next = [...manualDeadlines];
    final index = next.indexWhere(
      (task) => task.stableKey == deadline.stableKey,
    );
    if (index == -1) {
      next.add(deadline);
    } else {
      next[index] = deadline;
    }
    await _repository.saveManualDeadlines(next);
    manualDeadlines = next;
    reminderSchedulingFailed = false;
    notifyListeners();
    try {
      if (_notificationInitializer == null) {
        await NotificationService.init(requestPermissions: true);
      } else {
        await _notificationInitializer();
      }
      await _rescheduleNotifications();
    } catch (error) {
      reminderSchedulingFailed = true;
      debugPrint('Manual task saved; reminder scheduling needs attention.');
    }
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
    try {
      await _rescheduleNotifications();
      reminderSchedulingFailed = false;
    } catch (_) {
      reminderSchedulingFailed = true;
      debugPrint('Manual task deleted; reminder rescheduling needs repair.');
    }
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
    // Android stores scheduled notification copy at scheduling time.
    // Refresh it when the user changes languages; do not undo the preference
    // if optional platform scheduling is unavailable.
    try {
      if (allDeadlines.isNotEmpty) await _rescheduleNotifications();
    } catch (_) {
      reminderSchedulingFailed = true;
      debugPrint('Saved language; reminders need repair.');
      notifyListeners();
    }
    try {
      await _publishWidget();
    } catch (_) {
      debugPrint('Saved language; home widget refresh unavailable.');
    }
  }

  Future<void> disconnect() async {
    // Disconnect only the calendar sources. Completed manual, API and session
    // tasks must keep their state and individual reminder preferences.
    final calendarKeys = deadlines.map((item) => item.stableKey).toSet();
    final retainedCompleted = completedIds.difference(calendarKeys);
    final retainedTaskOffsets = <String, List<int>>{
      for (final entry in taskReminderOffsets.entries)
        if (!calendarKeys.contains(entry.key)) entry.key: entry.value,
    };

    await _repository.clearCalendarUrl();
    await _repository.clearAdditionalCalendarUrls();
    await _repository.clearCachedCalendarData();
    await _repository.saveCompletedIds(retainedCompleted);
    await _repository.saveTaskReminderOffsets(retainedTaskOffsets);
    deadlines = const [];
    additionalCalendarUrls = const [];
    calendarLabels = {};
    completedIds = retainedCompleted;
    taskReminderOffsets = retainedTaskOffsets;
    lastSync = null;
    calendarConnected = false;
    error = null;
    await _rescheduleNotifications();
    await _publishWidget();
    notifyListeners();
  }

  /// Called explicitly from Settings when Android permissions or timezone
  /// settings changed. Never clears the user's saved tasks.
  Future<bool> repairReminders() async {
    reminderRepairFailure = null;
    try {
      if (_notificationInitializer == null) {
        await NotificationService.init(requestPermissions: true);
      } else {
        await _notificationInitializer();
      }
    } catch (error) {
      reminderRepairFailure = ReminderRepairFailure.initializationFailed;
      debugPrint('Reminder initialization failed: ${error.runtimeType}');
      return false;
    }

    bool? enabled;
    try {
      if (_notificationPermissionChecker == null) {
        enabled = await NotificationService.notificationsEnabled();
      } else {
        enabled = await _notificationPermissionChecker();
      }
    } catch (error) {
      reminderRepairFailure = ReminderRepairFailure.permissionCheckFailed;
      debugPrint('Reminder permission check failed: ${error.runtimeType}');
      return false;
    }
    if (enabled == false) {
      reminderRepairFailure = ReminderRepairFailure.permissionDenied;
      return false;
    }

    try {
      await _rescheduleNotifications();
      reminderSchedulingFailed = false;
      notifyListeners();
      return true;
    } catch (error) {
      reminderSchedulingFailed = true;
      reminderRepairFailure = ReminderRepairFailure.schedulingFailed;
      debugPrint('Reminder scheduling failed: ${error.runtimeType}');
      notifyListeners();
      return false;
    }
  }

  Future<void> _rescheduleNotifications() {
    if (_reminderScheduler != null) return _reminderScheduler();
    return NotificationService.scheduleAll(
      allDeadlines,
      reminderOffsetsHours: reminderOffsets,
      completedIds: completedIds,
      taskReminderOffsets: taskReminderOffsets,
      arabic: locale.languageCode == 'ar',
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
