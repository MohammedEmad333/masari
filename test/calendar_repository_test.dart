import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moodle_reminder/models/deadline.dart';
import 'package:moodle_reminder/services/calendar_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final saved = <String, String>{};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    saved.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final key = args['key'] as String?;
          if (call.method == 'read') return saved[key];
          if (call.method == 'write') saved[key!] = args['value'] as String;
          if (call.method == 'delete') saved.remove(key);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'cached overdue and upcoming assignments survive offline loading',
    () async {
      final now = DateTime.now();
      final past = Deadline(
        uid: 'past',
        title: 'Late assignment',
        due: now.subtract(const Duration(days: 1)),
      );
      final future = Deadline(
        uid: 'future',
        title: 'Upcoming quiz',
        due: now.add(const Duration(days: 1)),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'deadline_cache_v2',
        jsonEncode([future.toJson(), past.toJson()]),
      );

      final restored = await CalendarRepository().loadCachedDeadlines();
      expect(restored.map((d) => d.uid).toList(), ['past', 'future']);
    },
  );

  test(
    'per-task overrides are saved, restored and cleared on disconnect',
    () async {
      final repository = CalendarRepository();
      await repository.saveTaskReminderOffsets({
        'assignment-id': [24, 6],
        'no-early-alerts': [],
      });

      final restored = await repository.loadTaskReminderOffsets();
      expect(restored['assignment-id'], [24, 6]);
      expect(restored['no-early-alerts'], isEmpty);

      await repository.clearCachedCalendarData();
      expect(await repository.loadTaskReminderOffsets(), isEmpty);
    },
  );

  test('global reminder selection remains disabled after restart', () async {
    final repository = CalendarRepository();
    await repository.saveReminderOffsets([]);
    expect(await CalendarRepository().loadReminderOffsets(), isEmpty);
  });

  test(
    'invalid saved offsets do not silently re-enable early alerts',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('reminder_offsets_hours', ['invalid', '-2']);
      expect(await CalendarRepository().loadReminderOffsets(), isEmpty);
    },
  );

  test('missing reminder preferences retain safe defaults', () async {
    expect(await CalendarRepository().loadReminderOffsets(), [24, 6, 1]);
  });

  test(
    'sync prefers custom period and preserves original stored URL',
    () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          'BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:custom-1\n'
          'SUMMARY:Custom period assignment\nDTSTART:20300504T100000Z\n'
          'END:VEVENT\nEND:VCALENDAR',
          200,
        );
      });
      final repository = CalendarRepository(client: client);
      const original =
          'https://moodle.example.edu/calendar/export_execute.php'
          '?userid=7&authtoken=secret&preset_time=monthnow';
      final values = await repository.sync(calendarUrl: original);
      expect(values.single.uid, 'custom-1');
      expect(requests.length, 1);
      expect(requests.single.queryParameters['preset_time'], 'custom');
      expect(await repository.loadCalendarUrl(), original);
      client.close();
    },
  );

  test('failed custom period retries original export', () async {
    final periods = <String?>[];
    final client = MockClient((request) async {
      final period = request.url.queryParameters['preset_time'];
      periods.add(period);
      if (period == 'custom') return http.Response('Bad request', 400);
      return http.Response(
        'BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:original-1\n'
        'SUMMARY:Original period assignment\nDTSTART:20300504T100000Z\n'
        'END:VEVENT\nEND:VCALENDAR',
        200,
      );
    });
    final repository = CalendarRepository(client: client);
    final values = await repository.sync(
      calendarUrl:
          'https://moodle.example.edu/calendar/export_execute.php'
          '?userid=7&authtoken=secret&preset_time=monthnow',
    );
    expect(periods, ['custom', 'monthnow']);
    expect(values.single.uid, 'original-1');
    client.close();
  });

  test(
    'both export failures retain offline cache and report failure',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('deadline_cache_v2', 'existing-cache');
      final periods = <String?>[];
      final client = MockClient((request) async {
        periods.add(request.url.queryParameters['preset_time']);
        return http.Response('Invalid authentication', 200);
      });
      final repository = CalendarRepository(client: client);
      await expectLater(
        repository.sync(
          calendarUrl:
              'https://moodle.example.edu/calendar/export_execute.php'
              '?authtoken=secret&preset_time=monthnow',
        ),
        throwsA(isA<CalendarSyncException>()),
      );
      expect(periods, ['custom', 'monthnow']);
      expect(prefs.getString('deadline_cache_v2'), 'existing-cache');
      client.close();
    },
  );

  test('HTTP sync failure preserves offline deadlines and timestamp', () async {
    final prefs = await SharedPreferences.getInstance();
    final deadline = Deadline(
      uid: 'cached',
      title: 'Saved quiz',
      due: DateTime.utc(2030, 1, 15),
    );
    final cached = jsonEncode([deadline.toJson()]);
    const lastSync = '2026-10-01T10:00:00.000';
    await prefs.setString('deadline_cache_v2', cached);
    await prefs.setString('last_sync_at', lastSync);

    final client = MockClient((request) async => http.Response('Offline', 503));
    final repository = CalendarRepository(client: client);

    await expectLater(
      repository.sync(calendarUrl: 'https://moodle.example/calendar.ics'),
      throwsA(isA<CalendarSyncException>()),
    );
    expect(prefs.getString('deadline_cache_v2'), cached);
    expect(prefs.getString('last_sync_at'), lastSync);
    expect((await repository.loadCachedDeadlines()).single.uid, 'cached');
    client.close();
  });

  test('invalid iCalendar response preserves previous cache', () async {
    final prefs = await SharedPreferences.getInstance();
    final deadline = Deadline(
      uid: 'persist',
      title: 'Offline assignment',
      due: DateTime.utc(2030, 2, 1),
    );
    final cached = jsonEncode([deadline.toJson()]);
    await prefs.setString('deadline_cache_v2', cached);

    final client = MockClient(
      (request) async => http.Response('<html>Login</html>', 200),
    );
    final repository = CalendarRepository(client: client);

    await expectLater(
      repository.sync(calendarUrl: 'https://moodle.example/calendar.ics'),
      throwsA(isA<CalendarSyncException>()),
    );
    expect(prefs.getString('deadline_cache_v2'), cached);
    client.close();
  });

  test('HTTP 200 Moodle invalid authentication is reported safely', () async {
    final client = MockClient((request) async {
      return http.Response('Invalid authentication', 200);
    });
    final repository = CalendarRepository(client: client);
    await expectLater(
      repository.sync(calendarUrl: 'https://moodle.example/calendar.ics'),
      throwsA(
        isA<CalendarSyncException>().having(
          (exception) => exception.message,
          'message',
          contains('rejected the private calendar authorization'),
        ),
      ),
    );
    client.close();
  });

  test('calendar response decodes UTF-8', () async {
    final bytes = utf8.encode(
      '\uFEFFBEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:arabic-1\n'
      'SUMMARY:واجب جامعي\nDTSTART:20300504T100000Z\n'
      'END:VEVENT\nEND:VCALENDAR',
    );
    final client = MockClient((request) async {
      return http.Response.bytes(
        bytes,
        200,
        headers: {'content-type': 'text/plain'},
      );
    });
    final repository = CalendarRepository(client: client);
    final deadlines = await repository.sync(
      calendarUrl: 'https://moodle.example/calendar.ics',
    );
    expect(deadlines.single.title, 'واجب جامعي');
    client.close();
  });

  test('Moodle disabled calendar export reports specific error', () async {
    final client = MockClient((request) async {
      return http.Response('no export', 200);
    });
    final repository = CalendarRepository(client: client);
    await expectLater(
      repository.sync(calendarUrl: 'https://moodle.example/calendar.ics'),
      throwsA(
        isA<CalendarSyncException>().having(
          (exception) => exception.message,
          'message',
          contains('disabled by the university server'),
        ),
      ),
    );
    client.close();
  });

  test('truncated calendar does not replace cached deadlines', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('deadline_cache_v2', 'previous-cache');
    final client = MockClient(
      (request) async => http.Response('BEGIN:VCALENDAR\nBEGIN:VEVENT', 200),
    );
    final repository = CalendarRepository(client: client);
    await expectLater(
      repository.sync(calendarUrl: 'https://moodle.example/calendar.ics'),
      throwsA(isA<CalendarSyncException>()),
    );
    expect(prefs.getString('deadline_cache_v2'), 'previous-cache');
    client.close();
  });

  test('HTML-wrapped calendar does not replace cache', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('deadline_cache_v2', 'previous-cache');
    final client = MockClient(
      (request) async =>
          http.Response('<html>BEGIN:VCALENDAR\nEND:VCALENDAR</html>', 200),
    );
    final repository = CalendarRepository(client: client);
    await expectLater(
      repository.sync(calendarUrl: 'https://moodle.example/calendar.ics'),
      throwsA(isA<CalendarSyncException>()),
    );
    expect(prefs.getString('deadline_cache_v2'), 'previous-cache');
    client.close();
  });

  test(
    'manual tasks persist with priority without affecting Moodle cache',
    () async {
      final repository = CalendarRepository();
      final manual = Deadline(
        uid: 'manual-1',
        title: 'Study chemistry',
        due: DateTime.utc(2030, 4, 1),
        priority: 3,
      );
      await repository.saveManualDeadlines([manual]);
      final restored = await CalendarRepository().loadManualDeadlines();
      expect(restored.single.title, 'Study chemistry');
      expect(restored.single.priority, 3);
      expect(await repository.loadCachedDeadlines(), isEmpty);
      await repository.clearCachedCalendarData();
      expect((await repository.loadManualDeadlines()).single.uid, 'manual-1');
    },
  );

  test('invalid manual task storage is handled safely', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('manual_deadlines_v1', 'not-json');
    expect(await CalendarRepository().loadManualDeadlines(), isEmpty);
  });

  test('priority defaults for legacy Moodle tasks', () {
    final deadline = Deadline.fromJson({
      'uid': 'legacy',
      'title': 'Old task',
      'due': '2030-01-01T10:00:00.000',
    });
    expect(deadline.priority, 1);
  });

  test('failed extra feed keeps cached deadlines', () async {
    final prefs = await SharedPreferences.getInstance();
    final cached = Deadline(
      uid: 'cached-extra',
      title: 'Previously downloaded assignment',
      due: DateTime.utc(2030, 5, 3),
    );
    await prefs.setString('deadline_cache_v2', jsonEncode([cached.toJson()]));
    final client = MockClient((request) async {
      if (request.url.host == 'secondary.example') {
        return http.Response('Unavailable', 503);
      }
      return http.Response(
        'BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:primary-1\n'
        'SUMMARY:Primary deadline\nDTSTART:20300504T100000Z\n'
        'END:VEVENT\nEND:VCALENDAR',
        200,
      );
    });
    final repository = CalendarRepository(client: client);
    final deadlines = await repository.sync(
      calendarUrl: 'https://primary.example/calendar.ics',
      additionalCalendarUrls: ['https://secondary.example/calendar.ics'],
    );
    expect(deadlines.length, 2);
    expect(deadlines.any((value) => value.uid == 'cached-extra'), isTrue);
    expect(deadlines.any((value) => value.uid == 'primary-1'), isTrue);
    expect(repository.lastSyncWarning, isNotNull);
    client.close();
  });

  test('additional calendar rejects non-HTTP URLs before storage', () async {
    final repository = CalendarRepository();
    await expectLater(
      repository.addAdditionalCalendarUrl('javascript:alert(1)'),
      throwsA(isA<CalendarSyncException>()),
    );
    await expectLater(
      repository.addAdditionalCalendarUrl('file:///private/calendar.ics'),
      throwsA(isA<CalendarSyncException>()),
    );
  });

  test('invalid persisted override data falls back to empty', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('task_reminder_offsets_v1', '{oops');
    expect(await CalendarRepository().loadTaskReminderOffsets(), isEmpty);
  });
}
