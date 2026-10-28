import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_assistant_client.dart';
import 'google_account_service.dart';
import 'oracle_ai_session_store.dart';

/// Explicit Google sign-in -> verified Oracle AI account/session exchange.
/// Only the existing Firebase ID token and App Check go to the Masari server.
class GoogleAiSessionClient {
  GoogleAiSessionClient({
    http.Client? client,
    Future<String?> Function()? idTokenProvider,
    Future<String?> Function()? appCheckProvider,
    OracleAiSessionStore? sessionStore,
    Uri? endpoint,
  }) : _http = client ?? http.Client(),
       _ownsHttp = client == null,
       _idTokenProvider = idTokenProvider ?? _getIdToken,
       _appCheckProvider = appCheckProvider ?? _getAppCheck,
       _store = sessionStore ?? OracleAiSessionStore(),
       _endpoint = endpoint ?? _defaultEndpoint();

  static const enabled = bool.fromEnvironment(
    'MASARI_GOOGLE_AI_LOGIN_ENABLED',
    defaultValue: false,
  );
  static Future<void>? _appCheckInit;
  final http.Client _http;
  final bool _ownsHttp;
  final Uri? _endpoint;
  final Future<String?> Function() _idTokenProvider;
  final Future<String?> Function() _appCheckProvider;
  final OracleAiSessionStore _store;

  static Uri? _defaultEndpoint() {
    final uri = Uri.tryParse(AiAssistantClient.configuredUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path != '/v1/assistant/ask') {
      return null;
    }
    return uri.replace(path: '/v1/assistant/google-session');
  }

  static Future<String?> _getIdToken() async {
    await GoogleAccountService.instance.initialize();
    return GoogleAccountService.instance.currentUser?.getIdToken(true);
  }

  static Future<String?> _getAppCheck() async {
    await GoogleAccountService.instance.initialize();
    _appCheckInit ??= FirebaseAppCheck.instance.activate(
      providerAndroid: kReleaseMode
          ? const AndroidPlayIntegrityProvider()
          : const AndroidDebugProvider(),
    );
    await _appCheckInit;
    return FirebaseAppCheck.instance.getToken();
  }

  /// The caller initiates Google sign-in explicitly via the Google UI first.
  Future<void> exchange() async {
    if (_endpoint == null ||
        _endpoint!.scheme != 'https' ||
        _endpoint!.userInfo.isNotEmpty ||
        _endpoint!.path != '/v1/assistant/google-session' ||
        _endpoint!.hasQuery ||
        _endpoint!.hasFragment) {
      throw const AiAssistantException('not_configured');
    }
    final String? token;
    final String? appCheck;
    try {
      token = await _idTokenProvider();
      appCheck = await _appCheckProvider();
    } catch (_) {
      throw const AiAssistantException('sign_in_required');
    }
    if (token == null || token.isEmpty) {
      throw const AiAssistantException('sign_in_required');
    }
    if (appCheck == null || appCheck.isEmpty) {
      throw const AiAssistantException('app_check_failed');
    }

    final http.Response response;
    try {
      response = await _http
          .post(
            _endpoint!,
            headers: {
              'Authorization': 'Bearer $token',
              'X-Firebase-AppCheck': appCheck,
            },
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const AiAssistantException('timeout');
    } catch (_) {
      throw const AiAssistantException('network_error');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AiAssistantException('sign_in_required');
    }
    if (response.statusCode != 200) {
      throw const AiAssistantException('service_unavailable');
    }
    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) throw const FormatException();
      final token = body['token'];
      final expiry = body['expiresAt'];
      if (token is! String || expiry is! String) {
        throw const FormatException();
      }
      final date = DateTime.tryParse(expiry);
      if (date == null) throw const FormatException();
      final googleUid = GoogleAccountService.instance.currentUser?.uid;
      if (googleUid == null || googleUid.isEmpty) {
        throw const AiAssistantException('sign_in_required');
      }
      await _store.save(token: token, expiresAt: date, googleUid: googleUid);
    } on AiAssistantException {
      rethrow;
    } on FormatException {
      throw const AiAssistantException('invalid_response');
    } catch (_) {
      throw const AiAssistantException('session_storage_error');
    }
  }

  void dispose() {
    if (_ownsHttp) _http.close();
  }
}
