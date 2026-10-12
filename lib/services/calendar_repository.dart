import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/deadline.dart';
import 'ics_parser.dart';
import 'calendar_source_merger.dart';

class CalendarSyncException implements Exception {
  const CalendarSyncException(this.message);
  final String message;

  @override
  String toString() => message;
}

class CalendarRepository {
  CalendarRepository({http.Client? client, FlutterSecureStorage? secureStorage})
    : _client = client ?? http.Client(),
      _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _secureCalendarUrlKey = 'moodle_calendar_url';
  static const _calendarSourcesKey = 'moodle_calendar_sources_v1';
  static const _legacyCalendarUrlKey = 'calendar_url';
  static const _cacheKey = 'deadline_cache_v2';
  static const _manualKey = 'manual_deadlines_v1';
  static const _legacyCacheKey = 'deadline_cache';
  static const _lastSyncKey = 'last_sync_at';
  static const _reminderOffsetsKey = 'reminder_offsets_hours';
  static const _taskOffsetsKey = 'task_reminder_offsets_v1';
  static const _completedIdsKey = 'completed_deadline_ids';
  static const _themeModeKey = 'theme_mode';
  static const _localeKey = 'locale';

  final http.Client _client;
  final FlutterSecureStorage _secureStorage;

  Future<void> migrateLegacyStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final current = await _secureStorage.read(key: _secureCalendarUrlKey);
    final legacy = prefs.getString(_legacyCalendarUrlKey);

    if ((current == null || current.isEmpty) &&
        legacy != null &&
        legacy.trim().isNotEmpty) {
      await _secureStorage.write(
        key: _secureCalendarUrlKey,
        value: legacy.trim(),
      );
    }
    if (legacy != null) await prefs.remove(_legacyCalendarUrlKey);

    if (!prefs.containsKey(_cacheKey) && prefs.containsKey(_legacyCacheKey)) {
      final oldCache = prefs.getString(_legacyCacheKey);
      if (oldCache != null) await prefs.setString(_cacheKey, oldCache);
      await prefs.remove(_legacyCacheKey);
    }
  }

  Future<String?> loadCalendarUrl() async {
    final value = await _secureStorage.read(key: _secureCalendarUrlKey);
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> saveCalendarUrl(String value) async {
    final url = value.trim();
    _validateUrl(url);
    await _secureStorage.write(key: _secureCalendarUrlKey, value: url);
  }

  Future<void> clearCalendarUrl() async {
    await _secureStorage.delete(key: _secureCalendarUrlKey);
  }

  /// Additional feeds are stored securely because Moodle export URLs can
  /// contain access tokens. The original feed remains the primary source.
  Future<List<String>> loadAdditionalCalendarUrls() async {
    final encoded = await _secureStorage.read(key: _calendarSourcesKey);
    if (encoded == null || encoded.isEmpty) return const [];
    try {
      final parsed = jsonDecode(encoded);
      if (parsed is! List) return const [];
      return parsed
          .whereType<String>()
          .where((url) {
            final uri = Uri.tryParse(url);
            return uri != null &&
                uri.hasAuthority &&
                (uri.scheme == 'https' || uri.scheme == 'http');
          })
          .toSet()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> addAdditionalCalendarUrl(String value) async {
    final url = value.trim();
    _validateUrl(url);
    if (url == await loadCalendarUrl()) return;
    final sources = await loadAdditionalCalendarUrls();
    if (sources.contains(url)) return;
    await _secureStorage.write(
      key: _calendarSourcesKey,
      value: jsonEncode([...sources, url]),
    );
  }

  Future<void> removeAdditionalCalendarUrl(String value) async {
    final sources = await loadAdditionalCalendarUrls();
    await _secureStorage.write(
      key: _calendarSourcesKey,
      value: jsonEncode(sources.where((url) => url != value).toList()),
    );
  }

  Future<List<Deadline>> loadCachedDeadlines() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_cacheKey);
    if (encoded == null || encoded.isEmpty) return const [];

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => Deadline.fromJson(Map<String, dynamic>.from(item)))
          .toList()
        ..sort((a, b) => a.due.compareTo(b.due));
    } catch (_) {
      return const [];
    }
  }

  Future<List<Deadline>> loadManualDeadlines() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_manualKey);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((entry) => Deadline.fromJson(Map<String, dynamic>.from(entry)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveManualDeadlines(List<Deadline> deadlines) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _manualKey,
      jsonEncode(deadlines.map((d) => d.toJson()).toList()),
    );
  }

  Future<List<Deadline>> sync({
    String? calendarUrl,
    List<String>? additionalCalendarUrls,
  }) async {
    final url = (calendarUrl ?? await loadCalendarUrl())?.trim();
    if (url == null || url.isEmpty) {
      throw const CalendarSyncException('Add your Moodle calendar URL first.');
    }
    _validateUrl(url);
    final additional =
        additionalCalendarUrls ?? await loadAdditionalCalendarUrls();
    final sources = <String, List<Deadline>>{'': await _fetchCalendar(url)};
    for (final extra in additional.toSet()) {
      if (extra == url) continue;
      _validateUrl(extra);
      // Stable source identities must not embed secret calendar tokens.
      final sourceId = extra.codeUnits
          .fold<int>(0, (hash, code) => ((hash * 31) + code) & 0x7fffffff)
          .toRadixString(16);
      sources['feed-$sourceId'] = await _fetchCalendar(extra);
    }
    // Commit only once all feeds have been downloaded and parsed.
    final upcoming = CalendarSourceMerger.merge(sources);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey,
      jsonEncode(upcoming.map((deadline) => deadline.toJson()).toList()),
    );
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
    await saveCalendarUrl(url);
    return upcoming;
  }

  Future<List<Deadline>> _fetchCalendar(String url) async {
    final response = await _client
        .get(Uri.parse(url), headers: const {'Accept': 'text/calendar,*/*'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw CalendarSyncException(
        'Moodle returned HTTP ${response.statusCode}. Check the calendar URL.',
      );
    }
    final calendarBody = response.body.trim();
    if (!calendarBody.startsWith('BEGIN:VCALENDAR') ||
        !calendarBody.endsWith('END:VCALENDAR')) {
      throw const CalendarSyncException(
        'The URL did not return a valid iCalendar feed.',
      );
    }
    return IcsParser.parse(calendarBody).toList();
  }

  Future<void> clearCachedCalendarData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await prefs.remove(_lastSyncKey);
    await prefs.remove(_completedIdsKey);
    await prefs.remove(_taskOffsetsKey);
  }

  Future<DateTime?> loadLastSync() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_lastSyncKey);
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<List<int>> loadReminderOffsets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_reminderOffsetsKey);
    if (raw == null) return const [24, 6, 1];
    if (raw.isEmpty) return const [];

    final values =
        raw
            .map(int.tryParse)
            .whereType<int>()
            .where((hours) => hours > 0)
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    // A saved selection is intentional, including an empty one. Never
    // silently enable reminders again after restoring user preferences.
    return values;
  }

  Future<void> saveReminderOffsets(List<int> values) async {
    final normalized = values.where((value) => value > 0).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _reminderOffsetsKey,
      normalized.map((value) => value.toString()).toList(),
    );
  }

  Future<Map<String, List<int>>> loadTaskReminderOffsets() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_taskOffsetsKey);
    if (encoded == null) return {};
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return {};
      final result = <String, List<int>>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String || entry.value is! List) continue;
        result[entry.key as String] = (entry.value as List)
            .whereType<int>()
            .where((value) => value > 0)
            .toSet()
            .toList();
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveTaskReminderOffsets(Map<String, List<int>> values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_taskOffsetsKey, jsonEncode(values));
  }

  Future<Set<String>> loadCompletedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_completedIdsKey) ?? const <String>[]).toSet();
  }

  Future<void> saveCompletedIds(Set<String> values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_completedIdsKey, values.toList()..sort());
  }

  Future<String> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeModeKey) ?? 'system';
  }

  Future<void> saveThemeMode(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, value);
  }

  Future<String> loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_localeKey) ?? 'en';
  }

  Future<void> saveLocale(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, value);
  }

  void _validateUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const CalendarSyncException('Enter a valid Moodle calendar URL.');
    }
  }
}
