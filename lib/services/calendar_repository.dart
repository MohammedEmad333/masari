import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/deadline.dart';
import 'ics_parser.dart';
import 'moodle_calendar_link.dart';
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
  static const _apiCacheKey = 'moodle_api_deadline_cache_v1';
  static const _sessionCacheKey = 'moodle_session_events_v1';
  static const _legacyCacheKey = 'deadline_cache';
  static const _lastSyncKey = 'last_sync_at';
  static const _reminderOffsetsKey = 'reminder_offsets_hours';
  static const _taskOffsetsKey = 'task_reminder_offsets_v1';
  static const _completedIdsKey = 'completed_deadline_ids';
  static const _themeModeKey = 'theme_mode';
  static const _localeKey = 'locale';
  static const _offlineModeKey = 'offline_study_mode_v1';

  final http.Client _client;
  final FlutterSecureStorage _secureStorage;
  String? lastSyncWarning;

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

  Future<void> clearAdditionalCalendarUrls() async {
    await _secureStorage.delete(key: _calendarSourcesKey);
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

  /// Cached non-secret assignment metadata for offline API access.
  Future<List<Deadline>> loadCachedApiDeadlines() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_apiCacheKey);
    if (raw == null) return const [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((value) => Deadline.fromJson(Map<String, dynamic>.from(value)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveCachedApiDeadlines(List<Deadline> values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _apiCacheKey,
      jsonEncode(values.map((value) => value.toJson()).toList()),
    );
  }

  Future<void> clearCachedApiDeadlines() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiCacheKey);
  }

  Future<List<Deadline>> loadSessionDeadlines() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionCacheKey);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => Deadline.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveSessionDeadlines(List<Deadline> values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sessionCacheKey,
      jsonEncode(values.map((value) => value.toJson()).toList()),
    );
  }

  Future<void> clearSessionDeadlines() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionCacheKey);
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
    List<String> additional;
    if (additionalCalendarUrls != null) {
      additional = additionalCalendarUrls;
    } else if (calendarUrl != null) {
      additional = const [];
    } else {
      additional = await loadAdditionalCalendarUrls();
    }
    lastSyncWarning = null;
    // A failed optional feed must not prevent the primary feed from updating.
    // Retain cached events for an unavailable feed until it works again.
    final previous = await loadCachedDeadlines();
    final sources = <String, List<Deadline>>{'': await _fetchCalendar(url)};
    var failedCount = 0;
    for (final extra in additional.toSet()) {
      if (extra == url) continue;
      try {
        _validateUrl(extra);
        // Stable source identities must not embed secret calendar tokens.
        final sourceId = extra.codeUnits
            .fold<int>(0, (hash, code) => ((hash * 31) + code) & 0x7fffffff)
            .toRadixString(16);
        sources['feed-$sourceId'] = await _fetchCalendar(extra);
      } catch (_) {
        failedCount++;
      }
    }
    final refreshed = CalendarSourceMerger.merge(sources);
    final retained = <String, Deadline>{};
    final now = DateTime.now();
    // Keep previously imported historical events even after Moodle's rolling
    // ICS export window moves on. A missing event does not prove deletion.
    // During partial feed failures keep the entire previous cache instead.
    for (final deadline in previous) {
      if (failedCount > 0 || deadline.due.isBefore(now)) {
        retained[deadline.stableKey] = deadline;
      }
    }
    // Fresh events win by stable UID, including revised deadlines and titles.
    for (final deadline in refreshed) {
      retained[deadline.stableKey] = deadline;
    }
    final upcoming = retained.values.toList();
    upcoming.sort((a, b) => a.due.compareTo(b.due));
    if (failedCount > 0) {
      lastSyncWarning = 'Additional calendars failed: $failedCount';
    }
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
    final preferred = MoodleCalendarLink.preferCustomPeriod(url);
    if (preferred != url) {
      try {
        return await _downloadCalendar(preferred);
      } on CalendarSyncException {
        // Moodle installations may reject custom ranges. Use the original
        // export period instead of disconnecting a working subscription.
      }
    }
    return _downloadCalendar(url);
  }

  Future<List<Deadline>> _downloadCalendar(String url) async {
    late final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse(url),
            headers: const {'Accept': 'text/calendar, text/plain, */*'},
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const CalendarSyncException(
        'Moodle calendar download timed out. Please retry.',
      );
    } on SocketException {
      throw const CalendarSyncException(
        'Could not reach the Moodle server. Check connectivity or DNS.',
      );
    } on http.ClientException {
      throw const CalendarSyncException(
        'Could not download the Moodle calendar. Check your connection.',
      );
    }
    if (response.statusCode != 200) {
      throw CalendarSyncException(
        'Moodle returned HTTP ${response.statusCode}. Check the calendar URL.',
      );
    }
    // The iCalendar standard uses UTF-8. Response.body may instead default
    // to Latin-1 when Moodle omits a charset from its text/* content type.
    final calendarBody = utf8
        .decode(response.bodyBytes, allowMalformed: true)
        .replaceFirst('\uFEFF', '')
        .trim();
    if (!calendarBody.startsWith('BEGIN:VCALENDAR') ||
        !calendarBody.endsWith('END:VCALENDAR')) {
      final lower = calendarBody.toLowerCase();
      // Older Moodle sites return HTTP 200 even for authentication failures.
      // Do not expose the server's response body or private export URL.
      if (lower.contains('invalid authentication') ||
          lower.contains('invalid token') ||
          lower.contains('invalid authtoken')) {
        throw const CalendarSyncException(
          'Moodle rejected the private calendar authorization. '
          'Generate a fresh subscription URL from Moodle.',
        );
      }
      if (lower == 'no export') {
        throw const CalendarSyncException(
          'Moodle calendar export is disabled by the university server.',
        );
      }
      if (RegExp(
        r'<!doctype\s+html\b|<html\b|<form\b',
        caseSensitive: false,
      ).hasMatch(calendarBody)) {
        throw const CalendarSyncException(
          'Moodle returned a web page instead of iCalendar data. '
          'The server may require sign-in or block app downloads.',
        );
      }
      if (calendarBody.isEmpty) {
        throw const CalendarSyncException(
          'Moodle returned an empty calendar response (HTTP 200).',
        );
      }
      throw const CalendarSyncException(
        'Moodle returned HTTP 200 but no iCalendar data. '
        'The server returned an unrecognized response.',
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

  Future<bool> loadOfflineMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_offlineModeKey) ?? false;
  }

  Future<void> saveOfflineMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_offlineModeKey, value);
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
