import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores optional Moodle Web Services credentials on device only.
/// Never puts tokens in SharedPreferences, URLs or logs.
class MoodleApiCredentialsStore {
  MoodleApiCredentialsStore(this._storage);

  final FlutterSecureStorage _storage;
  static const storageKey = 'moodle_api_credentials_v1';

  Future<void> save({required Uri server, required String token}) async {
    if (server.scheme != 'https' ||
        !server.hasAuthority ||
        server.userInfo.isNotEmpty ||
        server.hasQuery ||
        server.hasFragment) {
      throw const FormatException('A valid HTTPS Moodle server URL is required');
    }
    if (token.trim().isEmpty) {
      throw const FormatException('A Moodle API token is required');
    }
    await _storage.write(
      key: storageKey,
      value: jsonEncode({'server': server.toString(), 'token': token.trim()}),
    );
  }

  Future<({Uri server, String token})?> load() async {
    final raw = await _storage.read(key: storageKey);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      final server = Uri.tryParse(data['server'] as String? ?? '');
      final token = data['token'];
      if (server == null ||
          server.scheme != 'https' ||
          !server.hasAuthority ||
          server.userInfo.isNotEmpty ||
          server.hasQuery ||
          server.hasFragment ||
          token is! String ||
          token.trim().isEmpty) {
        return null;
      }
      return (server: server, token: token);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() => _storage.delete(key: storageKey);
}
