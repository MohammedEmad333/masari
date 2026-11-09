import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/services/oracle_encrypted_calendar_codec.dart';

void main() {
  test('Oracle calendar archive is client-encrypted and round-trips', () async {
    const url =
        'https://moodle.example.edu/calendar/export_execute.php?authtoken=private-token';
    final archive = await OracleEncryptedCalendarCodec.encrypt(
      urls: [url],
      passphrase: 'strong-example-passphrase',
    );
    expect(archive.keys.toSet(), {
      'version',
      'salt',
      'nonce',
      'ciphertext',
      'mac',
    });
    expect(archive.toString(), isNot(contains('private-token')));
    expect(
      await OracleEncryptedCalendarCodec.decrypt(
        archive: archive,
        passphrase: 'strong-example-passphrase',
      ),
      [url],
    );
    await expectLater(
      OracleEncryptedCalendarCodec.decrypt(
        archive: archive,
        passphrase: 'different-example-passphrase',
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('Oracle calendar archive rejects insecure URLs', () async {
    await expectLater(
      OracleEncryptedCalendarCodec.encrypt(
        urls: ['http://moodle.example.edu/feed?authtoken=private'],
        passphrase: 'strong-example-passphrase',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
