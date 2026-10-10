import 'package:flutter/material.dart';

import 'models/deadline.dart';
import 'services/calendar_repository.dart';
import 'services/notification_service.dart';

class AppController extends ChangeNotifier {
  AppController(this._repository);

  final CalendarRepository _repository;

  List<Deadline> deadlines = const [];
  Set<String> completedIds = {};
  List<int> reminderOffsets = const [24, 6, 1];
  Map<String, List<int>> taskReminderOffsets = {};
  DateTime? lastSync;
  bool busy = false;
  bool initialized = false;
  bool calendarConnected = false;
  String? error;
  ThemeMode themeMode = ThemeMode.system;
  Locale locale = const Locale('en');

  List<Deadline> get activeDeadlines => deadlines
      .where((deadline) => !completedIds.contains(deadline.stableKey))
      .toList();

  List<Deadline> get completedDeadlines => deadlines
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
    ]);

    calendarConnected = results[0] != null;
    deadlines = results[1] as List<Deadline>;
    reminderOffsets = results[2] as List<int>;
    completedIds = results[3] as Set<String>;
    lastSync = results[4] as DateTime?;
    themeMode = _parseThemeMode(results[5] as String);
    locale = Locale((results[6] as String) == 'ar' ? 'ar' : 'en');
    taskReminderOffsets = results[7] as Map<String, List<int>>;
    initialized = true;
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
    if (!calendarConnected || busy) return false;
    if (!silent) {
      busy = true;
      error = null;
      notifyListeners();
    }

    try {
      await _syncInternal();
      return true;
    } catch (exception) {
      if (!silent) error = _message(exception);
      return false;
    } finally {
      if (!silent) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _syncInternal() async {
    deadlines = await _repository.sync();
    lastSync = await _repository.loadLastSync();
    error = null;
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
    await NotificationService.scheduleAll(
      const [],
      reminderOffsetsHours: reminderOffsets,
    );
    notifyListeners();
  }

  Future<void> _rescheduleNotifications() {
    return NotificationService.scheduleAll(
      deadlines,
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
