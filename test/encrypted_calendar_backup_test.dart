import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/services/encrypted_calendar_backup.dart';

void main() {
  test('calendar feed backup encrypts URLs and decrypts with passphrase', () async {
    const url = 'https://moodle.example.edu/calendar/export_execute.php?authtoken=private-token';
    final archive = await EncryptedCalendarBackup.encrypt(
      urls: [url],
      passphrase: 'very-strong-passphrase-2026',
    );
    expect(archive.toString(), isNot(contains('private-token')));
    expect(
      await EncryptedCalendarBackup.decrypt(
        archive: archive,
        passphrase: 'very-strong-passphrase-2026',
      ),
      [url],
    );
    expect(
      () => EncryptedCalendarBackup.decrypt(
        archive: archive,
        passphrase: 'wrong-password-is-long',
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('calendar backup rejects insecure URLs and short passwords', () async {
    expect(
      () => EncryptedCalendarBackup.encrypt(
        urls: ['http://moodle.example.edu/feed?authtoken=abc'],
        passphrase: 'very-strong-passphrase-2026',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => EncryptedCalendarBackup.encrypt(
        urls: ['https://moodle.example.edu/feed'],
        passphrase: 'short',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
