import 'dart:async';
import 'dart:convert';

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
       _endpoint =
           assistantEndpoint ?? Uri.tryParse(AiAssistantClient.configuredUrl);

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
      // Prevent a previous account's Oracle token from surviving a switch.
      await _store.clear();
      await GoogleAccountService.instance.initialize();
      final user = GoogleAccountService.instance.currentUser;
      if (user == null) {
        throw const AiAssistantException('sign_in_required');
      }
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        throw const AiAssistantException('sign_in_required');
      }
      final String? appCheck;
      try {
        appCheck = await AiAssistantClient.getAppCheckToken();
      } catch (_) {
        // Never expose provider exception details, tokens, or device identifiers.
        throw const AiAssistantException('app_check_failed');
      }
      if (appCheck == null || appCheck.isEmpty) {
        throw const AiAssistantException('app_check_failed');
      }
      final response = await _client
          .post(
            endpoint.replace(path: '/v1/auth/google'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
              'X-Firebase-AppCheck': appCheck,
            },
            body: '{}',
          )
          .timeout(const Duration(seconds: 20));
      // Only recognize a fixed allowlist of server errors; never surface
      // arbitrary response text or authentication credentials to the UI.
      String? serverError;
      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic> && body['error'] is String) {
          serverError = body['error'] as String;
        }
      } catch (_) {
        // Non-JSON gateway responses are treated by HTTP status below.
      }
      if (response.statusCode == 401) {
        throw const AiAssistantException('google_auth_rejected');
      }
      if (response.statusCode == 403) {
        throw AiAssistantException(
          serverError == 'app_check_required' || serverError == 'app_check_failed'
              ? 'app_check_failed'
              : 'google_auth_forbidden',
        );
      }
      if (response.statusCode == 429) {
        throw const AiAssistantException('quota_exceeded');
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
      final currentUid = GoogleAccountService.instance.currentUser?.uid;
      if (currentUid == null || currentUid != user.uid) {
        throw const AiAssistantException('sign_in_required');
      }
      await _store.save(token: token, expiresAt: expiry, googleUid: user.uid);
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
