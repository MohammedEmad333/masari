import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moodle_reminder/app_controller.dart';
import 'package:moodle_reminder/services/calendar_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final stored = <String, String>{};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    stored.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final key = args['key'] as String?;
          if (call.method == 'read') return stored[key];
          if (call.method == 'write') stored[key!] = args['value'] as String;
          if (call.method == 'delete') stored.remove(key);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'reminder failure never marks successful calendar sync as failed',
    () async {
      const url = 'https://moodle.example/calendar.ics';
      const calendar =
          'BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:quiz-1\n'
            'SUMMARY:Quiz\nDTSTART:20300504T100000Z\n'
            'END:VEVENT\nEND:VCALENDAR';
      final client = MockClient((request) async {
        return http.Response(calendar, 200);
      });
      final repository = CalendarRepository(client: client);
      await repository.sync(calendarUrl: url);
  
      var attempts = 0;
      final controller = AppController(
        repository,
        reminderScheduler: () async {
          attempts++;
          throw StateError('Android notifications unavailable');
        },
      );
      controller.calendarConnected = true;
  
      expect(await controller.sync(), isTrue);
      expect(controller.error, isNull);
      expect(controller.reminderSchedulingFailed, isTrue);
      expect(controller.deadlines.single.uid, 'quiz-1');
      expect(controller.lastSync, isNotNull);
      expect(attempts, 1);
  
      controller.dispose();
      client.close();
    },
  );

  test('failed calendar download still reports actual HTTP error', () async {
    const url = 'https://moodle.example/calendar.ics';
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      if (requests == 1) {
        return http.Response('BEGIN:VCALENDAR\nEND:VCALENDAR', 200);
      }
      return http.Response('Service unavailable', 503);
    });
    final repository = CalendarRepository(client: client);
    await repository.sync(calendarUrl: url);
    var scheduled = false;
    final controller = AppController(
      repository,
      reminderScheduler: () async => scheduled = true,
    );
    controller.calendarConnected = true;

    expect(await controller.sync(), isFalse);
    expect(controller.error, contains('HTTP 503'));
    expect(controller.reminderSchedulingFailed, isFalse);
    expect(scheduled, isFalse);

    controller.dispose();
    client.close();
  });
}
