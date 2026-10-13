import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moodle_reminder/models/deadline.dart';
import 'package:moodle_reminder/services/calendar_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('restores API deadlines across repositories', () async {
    final deadline = Deadline(
      uid: 'moodle-api:10:20',
      title: 'Lab report',
      course: 'Physics',
      due: DateTime.utc(2030, 2, 3),
    );
    final first = CalendarRepository();
    await first.saveCachedApiDeadlines([deadline]);

    final restored = await CalendarRepository().loadCachedApiDeadlines();
    expect(restored, hasLength(1));
    expect(restored.single.stableKey, 'moodle-api:10:20');
    expect(restored.single.title, 'Lab report');
    await first.clearCachedApiDeadlines();
    expect(await first.loadCachedApiDeadlines(), isEmpty);
  });

  test('ignores damaged API cache without losing other sources', () async {
    SharedPreferences.setMockInitialValues({
      'moodle_api_deadline_cache_v1': 'not-json',
    });
    final values = await CalendarRepository().loadCachedApiDeadlines();
    expect(values, isEmpty);
  });
}
