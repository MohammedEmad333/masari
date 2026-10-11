import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moodle_reminder/models/deadline.dart';
import 'package:moodle_reminder/services/calendar_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

  test('truncated calendar does not replace cached deadlines', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('deadline_cache_v2', 'previous-cache');
    final client = MockClient(
      (request) async => http.Response('BEGIN:VCALENDAR\\nBEGIN:VEVENT', 200),
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
      (request) async => http.Response(
        '<html>BEGIN:VCALENDAR\\nEND:VCALENDAR</html>',
        200,
      ),
    );
    final repository = CalendarRepository(client: client);
    await expectLater(
      repository.sync(calendarUrl: 'https://moodle.example/calendar.ics'),
      throwsA(isA<CalendarSyncException>()),
    );
    expect(prefs.getString('deadline_cache_v2'), 'previous-cache');
    client.close();
  });

  test('invalid persisted override data falls back to empty', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('task_reminder_offsets_v1', '{oops');
    expect(await CalendarRepository().loadTaskReminderOffsets(), isEmpty);
  });
}
