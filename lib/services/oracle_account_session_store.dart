import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'oracle_ai_session_store.dart' show OracleAiSession;

/// Account sessions have their own secure-storage namespace. They must never
/// inherit an unrelated legacy AI pairing/session token.
class OracleAccountSessionStore {
  OracleAccountSessionStore({FlutterSecureStorage? storage})
    : _storage =
          storage ?? const FlutterSecureStorage(aOptions: AndroidOptions());

  static const _tokenKey = 'masari_account_oracle_session_token_v1';
  static const _expiryKey = 'masari_account_oracle_session_expiry_v1';
  static const _googleUidKey = 'masari_account_oracle_google_uid_v1';
  static const _enrolledGoogleUidKey =
      'masari_account_oracle_enrolled_google_uid_v1';

  final FlutterSecureStorage _storage;

  Future<OracleAiSession?> readForGoogle(String? uid) async {
    if (uid == null || uid.isEmpty) return null;
    try {
      if (await _storage.read(key: _googleUidKey) != uid) return null;
      return read();
    } catch (_) {
      return null;
    }
  }

  Future<OracleAiSession?> read() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      final expiry = await _storage.read(key: _expiryKey);
      if (token == null || expiry == null) return null;
      final parsed = DateTime.tryParse(expiry)?.toUtc();
      if (parsed == null) return null;
      final session = OracleAiSession(token, parsed);
      if (!session.isValid) {
        await clear();
        return null;
      }
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<void> save({
    required String token,
    required DateTime expiresAt,
    required String googleUid,
  }) async {
    if (googleUid.isEmpty) throw ArgumentError('Missing Google account');
    final session = OracleAiSession(token, expiresAt.toUtc());
    if (!session.isValid) {
      throw ArgumentError('Invalid or expired Oracle session');
    }
    try {
      await clear();
      await _storage.write(key: _tokenKey, value: token);
      await _storage.write(
        key: _expiryKey,
        value: expiresAt.toUtc().toIso8601String(),
      );
      await _storage.write(key: _googleUidKey, value: googleUid);
    } catch (_) {
      await clear();
      rethrow;
    }
  }

  Future<String?> enrolledGoogleUid() async {
    try {
      return await _storage.read(key: _enrolledGoogleUidKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> rememberEnrollment(String googleUid) async {
    if (googleUid.isEmpty) throw ArgumentError('Missing Google account');
    await _storage.write(key: _enrolledGoogleUidKey, value: googleUid);
  }

  Future<void> forgetEnrollment() async {
    await _storage.delete(key: _enrolledGoogleUidKey);
  }

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _expiryKey);
    await _storage.delete(key: _googleUidKey);
  }
}
