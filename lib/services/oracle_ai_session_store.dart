import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Oracle AI sessions are independent from Google sign-in/backup credentials.
/// Never persist a pairing code, only its short-lived issued session.
class OracleAiSession {
  const OracleAiSession(this.token, this.expiresAt);
  final String token;
  final DateTime expiresAt;

  bool get isValid =>
      RegExp(r'^msr_[0-9a-f]{64}$').hasMatch(token) &&
      expiresAt.isAfter(DateTime.now().toUtc());
}

class OracleAiSessionStore {
  OracleAiSessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(),
        );

  static const _tokenKey = 'masari_ai_oracle_session_token';
  static const _expiryKey = 'masari_ai_oracle_session_expiry';
  final FlutterSecureStorage _storage;

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
      // Fail closed on storage errors; never treat missing credentials as
      // proof of authentication.
      return null;
    }
  }

  Future<void> save({required String token, required DateTime expiresAt}) async {
    final session = OracleAiSession(token, expiresAt.toUtc());
    if (!session.isValid) {
      throw ArgumentError('Invalid or expired Oracle session');
    }
    try {
      await _storage.write(key: _tokenKey, value: token);
      await _storage.write(
        key: _expiryKey,
        value: expiresAt.toUtc().toIso8601String(),
      );
    } catch (_) {
      await clear();
      rethrow;
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _expiryKey);
  }
}
