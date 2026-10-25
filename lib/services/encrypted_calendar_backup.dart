import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// An independently encrypted backup of Moodle ICS feed URLs.
/// Firebase receives only ciphertext; the user's passphrase never leaves
/// this device and is never saved to the account.
class EncryptedCalendarBackup {
  const EncryptedCalendarBackup(this.firestore);

  final FirebaseFirestore firestore;

  static const _iterations = 210000;
  static final _aes = AesGcm.with256bits();

  static List<int> _randomBytes(int length) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }

  static Future<SecretKey> _key(String passphrase, List<int> salt) {
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: 256,
    );
    return kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  static void _checkPassphrase(String passphrase) {
    if (passphrase.length < 12) {
      throw ArgumentError('Backup passphrase must be at least 12 characters.');
    }
  }

  static void _validateUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Expected a valid HTTPS calendar feed URL.');
    }
  }

  static Future<Map<String, dynamic>> encrypt({
    required List<String> urls,
    required String passphrase,
  }) async {
    _checkPassphrase(passphrase);
    for (final url in urls) {
      _validateUrl(url);
    }
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(urls)),
      secretKey: await _key(passphrase, salt),
      nonce: nonce,
    );
    return {
      'version': 1,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  static Future<List<String>> decrypt({
    required Map<String, dynamic> archive,
    required String passphrase,
  }) async {
    _checkPassphrase(passphrase);
    if (archive['version'] != 1) {
      throw const FormatException('Unsupported calendar backup version.');
    }
    final box = SecretBox(
      base64Decode(archive['ciphertext'] as String),
      nonce: base64Decode(archive['nonce'] as String),
      mac: Mac(base64Decode(archive['mac'] as String)),
    );
    final plain = await _aes.decrypt(
      box,
      secretKey: await _key(passphrase, base64Decode(archive['salt'] as String)),
    );
    final decoded = jsonDecode(utf8.decode(plain));
    if (decoded is! List) {
      throw const FormatException('Invalid backup payload.');
    }
    final urls = decoded.cast<String>();
    for (final url in urls) {
      _validateUrl(url);
    }
    return urls;
  }

  DocumentReference<Map<String, dynamic>> _document(User user) => firestore
      .collection('users')
      .doc(user.uid)
      .collection('calendarSecrets')
      .doc('v1');

  Future<void> upload({
    required User user,
    required List<String> urls,
    required String passphrase,
  }) async {
    final archive = await encrypt(urls: urls, passphrase: passphrase);
    await _document(user).set({
      ...archive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<String>?> download({
    required User user,
    required String passphrase,
  }) async {
    final data = (await _document(user).get()).data();
    if (data == null) return null;
    return decrypt(archive: data, passphrase: passphrase);
  }
}
