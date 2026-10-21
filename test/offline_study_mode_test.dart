import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/app_controller.dart';
import 'package:moodle_reminder/services/calendar_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('offline study mode is remembered across app sessions', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = CalendarRepository();
    final controller = AppController(repository);

    expect(controller.hasConnection, isFalse);
    expect(await repository.loadOfflineMode(), isFalse);

    await controller.enableOfflineMode();

    expect(controller.offlineMode, isTrue);
    expect(controller.hasConnection, isTrue);
    expect(await CalendarRepository().loadOfflineMode(), isTrue);
  });
}
