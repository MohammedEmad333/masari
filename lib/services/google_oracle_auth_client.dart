import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_assistant_client.dart';
import 'google_account_service.dart';
import 'oracle_ai_session_store.dart';

/// Opt-in until the Google exchange endpoint is deployed and verified.
class GoogleOracleAuthClient {
  GoogleOracleAuthClient({
    http.Client? client,
    OracleAiSessionStore? store,
    Uri? assistantEndpoint,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _store = store ?? OracleAiSessionStore(),
       _endpoint = assistantEndpoint ??
           Uri.tryParse(AiAssistantClient.configuredUrl);

  static const enabled = bool.fromEnvironment(
    'MASARI_GOOGLE_ORACLE_AUTH_ENABLED',
    defaultValue: false,
  );

  final http.Client _client;
  final bool _ownsClient;
  final OracleAiSessionStore _store;
  final Uri? _endpoint;

  Future<void> exchange() async {
    if (!enabled) throw const AiAssistantException('not_configured');
    final endpoint = _endpoint;
    if (endpoint == null ||
        endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        endpoint.path != '/v1/assistant/ask') {
      throw const AiAssistantException('not_configured');
    }
    try {
      await GoogleAccountService.instance.initialize();
      final user = GoogleAccountService.instance.currentUser;
      if (user == null) {
        throw const AiAssistantException('sign_in_required');
      }
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        throw const AiAssistantException('sign_in_required');
      }
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kReleaseMode
            ? const AndroidPlayIntegrityProvider()
            : const AndroidDebugProvider(),
      );
      final appCheck = await FirebaseAppCheck.instance.getToken();
      if (appCheck == null || appCheck.isEmpty) {
        throw const AiAssistantException('app_check_failed');
      }
      final response = await _client.post(
        endpoint.replace(path: '/v1/auth/google'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
          'X-Firebase-AppCheck': appCheck,
        },
        body: '{}',
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const AiAssistantException('sign_in_required');
      }
      if (response.statusCode != 200) {
        throw const AiAssistantException('service_unavailable');
      }
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) {
        throw const AiAssistantException('invalid_response');
      }
      final token = payload['token'];
      final expiry = DateTime.tryParse(payload['expiresAt']?.toString() ?? '');
      if (token is! String || expiry == null) {
        throw const AiAssistantException('invalid_response');
      }
      await _store.save(token: token, expiresAt: expiry);
    } on AiAssistantException {
      rethrow;
    } on TimeoutException {
      throw const AiAssistantException('timeout');
    } catch (_) {
      throw const AiAssistantException('network_error');
    }
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
