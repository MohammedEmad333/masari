import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Client-side encrypted Moodle calendar links, independent of Firebase.
/// Neither the passphrase nor plaintext URL is sent to Oracle.
class OracleEncryptedCalendarCodec {
  const OracleEncryptedCalendarCodec._();

  static final _aes = AesGcm.with256bits();

  static Future<SecretKey> _deriveKey(
    String passphrase,
    List<int> salt,
  ) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 210000,
    bits: 256,
  ).deriveKey(
    secretKey: SecretKey(utf8.encode(passphrase)),
    nonce: salt,
  );

  static void _validatePassphrase(String passphrase) {
    if (passphrase.length < 12) {
      throw ArgumentError('Passphrase must be at least 12 characters.');
    }
  }

  static void _validateUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Expected an HTTPS calendar URL.');
    }
  }

  static Future<Map<String, dynamic>> encrypt({
    required List<String> urls,
    required String passphrase,
  }) async {
    _validatePassphrase(passphrase);
    for (final url in urls) {
      _validateUrl(url);
    }
    final rng = Random.secure();
    final salt = List<int>.generate(16, (_) => rng.nextInt(256));
    final nonce = List<int>.generate(12, (_) => rng.nextInt(256));
    final secret = await _aes.encrypt(
      utf8.encode(jsonEncode(urls)),
      secretKey: await _deriveKey(passphrase, salt),
      nonce: nonce,
    );
    return {
      'version': 1,
      'salt': base64Encode(salt),
      'nonce': base64Encode(secret.nonce),
      'ciphertext': base64Encode(secret.cipherText),
      'mac': base64Encode(secret.mac.bytes),
    };
  }

  static Future<List<String>> decrypt({
    required Map<String, dynamic> archive,
    required String passphrase,
  }) async {
    _validatePassphrase(passphrase);
    if (archive['version'] != 1) {
      throw const FormatException('Unsupported encrypted archive.');
    }
    final box = SecretBox(
      base64Decode(archive['ciphertext'] as String),
      nonce: base64Decode(archive['nonce'] as String),
      mac: Mac(base64Decode(archive['mac'] as String)),
    );
    final plain = await _aes.decrypt(
      box,
      secretKey: await _deriveKey(
        passphrase,
        base64Decode(archive['salt'] as String),
      ),
    );
    final decoded = jsonDecode(utf8.decode(plain));
    if (decoded is! List) throw const FormatException('Invalid calendar archive.');
    final urls = decoded.cast<String>();
    for (final url in urls) {
      _validateUrl(url);
    }
    return urls;
  }
}
