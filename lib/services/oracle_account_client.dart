import 'dart:async';
import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'oracle_ai_session_store.dart' show OracleAiSession;
import 'oracle_account_session_store.dart';

/// Oracle is the account authority. Google only supplies a verified OIDC
/// identity at sign-in; Firebase Auth and Firestore are never consulted.
class OracleAccountClient {
  OracleAccountClient({
    http.Client? client,
    OracleAccountSessionStore? sessions,
    Uri? endpoint,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _sessions = sessions ?? OracleAccountSessionStore(),
       _endpoint = endpoint ?? Uri.tryParse(configuredUrl);

  static const configuredUrl = String.fromEnvironment(
    'MASARI_ACCOUNTS_API_URL',
  );
  static const _googleWebClientId =
      '657266784006-ai622s0cibo6t9kpld590pruvgccib48.apps.googleusercontent.com';

  static bool get enabled {
    final uri = Uri.tryParse(configuredUrl);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        (uri.path.isEmpty || uri.path == '/');
  }

  final http.Client _client;
  final bool _ownsClient;
  final OracleAccountSessionStore _sessions;
  final Uri? _endpoint;

  bool _initialized = false;
  GoogleSignInAccount? _googleAccount;

  Future<void> initialize() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: _googleWebClientId);
    _initialized = true;
  }

  Uri _url(String path) {
    final uri = _endpoint;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw StateError('Oracle account API is not configured.');
    }
    return uri.replace(path: path);
  }

  Future<OracleAiSession?> currentSession() async {
    await initialize();
    _googleAccount ??= await GoogleSignIn.instance
        .attemptLightweightAuthentication();
    final account = _googleAccount;
    if (account == null) return null;
    final stored = await _sessions.readForGoogle(account.id);
    if (stored != null) return stored;

    // Silent renewal is allowed only for an explicitly enrolled account.
    // Never create an Oracle account just because a Google session exists.
    if (await _sessions.enrolledGoogleUid() != account.id) return null;
    try {
      await _exchangeGoogle(account);
      return await _sessions.readForGoogle(account.id);
    } catch (_) {
      // Network outages do not prevent offline tasks and calendars.
      return null;
    }
  }

  Future<void> signIn() async {
    await initialize();
    final account = await GoogleSignIn.instance.authenticate();
    await _sessions.clear();
    await _exchangeGoogle(account, enroll: true);
  }

  Future<void> _exchangeGoogle(
    GoogleSignInAccount account, {
    bool enroll = false,
  }) async {
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Google identity token unavailable.');
    }
    final exchangeRequest = http.Request('POST', _url('/v1/auth/google-oidc'));
    exchangeRequest.followRedirects = false;
    exchangeRequest.headers.addAll({
      'Authorization': 'Bearer $idToken',
      'Content-Type': 'application/json',
    });
    // Only explicit, interactive sign-in may create a new Oracle account.
    exchangeRequest.body = enroll ? '{"enroll":true}' : '{}';
    final exchangeStream = await _client
        .send(exchangeRequest)
        .timeout(const Duration(seconds: 20));
    final response = await http.Response.fromStream(exchangeStream);
    if (response.statusCode != 200) {
      throw StateError('Oracle account sign-in failed.');
    }
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic> ||
        json['token'] is! String ||
        json['expiresAt'] is! String) {
      throw const FormatException('Invalid account session response.');
    }
    final expiresAt = DateTime.tryParse(json['expiresAt'] as String);
    if (expiresAt == null) {
      throw const FormatException('Invalid session expiry.');
    }
    await _sessions.save(
      token: json['token'] as String,
      expiresAt: expiresAt,
      googleUid: account.id,
    );
    await _sessions.rememberEnrollment(account.id);
    _googleAccount = account;
  }

  Future<http.Response> request(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, String> headers = const {},
  }) async {
    final session = await currentSession();
    if (session == null || !session.isValid) {
      throw StateError('Sign in to Oracle first.');
    }
    final request = http.Request(method, _url(path));
    request.followRedirects = false;
    request.headers.addAll({
      'Authorization': 'Bearer ${session.token}',
      'Content-Type': 'application/json',
      ...headers,
    });
    if (data != null) request.body = jsonEncode(data);
    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 20));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode == 401) {
      await _sessions.clear();
      throw StateError('Oracle session expired. Sign in again.');
    }
    if (response.statusCode >= 500) {
      throw StateError('Oracle account server unavailable.');
    }
    return response;
  }

  Future<Map<String, dynamic>> profile() async {
    final response = await request('GET', '/v1/account/me');
    if (response.statusCode != 200) throw StateError('Account unavailable.');
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<Map<String, dynamic>> updateName(String name) async {
    final response = await request(
      'PATCH',
      '/v1/account/me',
      data: {'displayName': name.trim()},
    );
    if (response.statusCode != 200) {
      throw StateError('Could not update profile.');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<void> upload(String kind, Map<String, dynamic> payload) async {
    final response = await request(
      'PUT',
      _backupPath(kind),
      data: {'data': payload},
    );
    if (response.statusCode != 200) throw StateError('Backup failed.');
  }

  /// The snapshot revision is checked atomically by PostgreSQL on upload.
  /// A missing document has revision zero.
  Future<({Map<String, dynamic>? data, int revision})> downloadSnapshot(
    String kind,
  ) async {
    final response = await request('GET', _backupPath(kind));
    if (response.statusCode == 404) return (data: null, revision: 0);
    if (response.statusCode != 200) throw StateError('Restore failed.');
    final body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    final revision = body['revision'];
    if (revision is! int || revision < 1) {
      throw const FormatException('Invalid backup revision.');
    }
    return (
      data: Map<String, dynamic>.from(body['data'] as Map),
      revision: revision,
    );
  }

  Future<Map<String, dynamic>?> download(String kind) async {
    final snapshot = await downloadSnapshot(kind);
    return snapshot.data;
  }

  /// Returns false on an HTTP 409 conflict; caller must re-read and re-merge.
  Future<bool> uploadIfCurrent(
    String kind,
    Map<String, dynamic> payload, {
    required int revision,
  }) async {
    if (revision < 0) throw ArgumentError.value(revision, 'revision');
    final response = await request(
      'PUT',
      _backupPath(kind),
      data: {'data': payload},
      headers: {'X-Backup-Revision': '$revision'},
    );
    if (response.statusCode == 409) return false;
    if (response.statusCode != 200) throw StateError('Backup failed.');
    return true;
  }

  Future<void> deleteBackup(String kind) async {
    final response = await request('DELETE', _backupPath(kind));
    if (response.statusCode != 200) throw StateError('Delete failed.');
  }

  String _backupPath(String kind) {
    if (kind != 'personal' && kind != 'calendar') {
      throw ArgumentError.value(kind, 'kind', 'Unknown backup type');
    }
    return '/v1/backups/$kind';
  }

  Future<void> deleteAccount() async {
    final response = await request(
      'DELETE',
      '/v1/account/me',
      headers: {'X-Confirm-Account-Deletion': 'delete-my-account'},
    );
    if (response.statusCode != 200) {
      throw StateError('Could not delete Oracle account.');
    }
    await _sessions.clear();
    await _sessions.forgetEnrollment();
    await GoogleSignIn.instance.signOut();
    _googleAccount = null;
  }

  Future<void> signOut() async {
    try {
      final session = await currentSession();
      if (session != null) {
        await request('POST', '/v1/auth/logout');
      }
    } catch (_) {
      // Local sign-out must still work offline. A remote session may remain
      // valid until its one-hour expiry; report that via privacy documentation.
    } finally {
      await _sessions.clear();
      await _sessions.forgetEnrollment();
      if (_initialized) await GoogleSignIn.instance.signOut();
      _googleAccount = null;
    }
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
