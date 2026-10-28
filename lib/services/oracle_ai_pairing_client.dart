import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_assistant_client.dart';
import 'oracle_ai_session_store.dart';

class OracleAiPairingClient {
  OracleAiPairingClient({
    http.Client? client,
    OracleAiSessionStore? store,
    Uri? endpoint,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _store = store ?? OracleAiSessionStore(),
       _endpoint = endpoint ?? Uri.tryParse(AiAssistantClient.configuredUrl);

  final http.Client _client;
  final bool _ownsClient;
  final OracleAiSessionStore _store;
  final Uri? _endpoint;

  Future<void> pair(String code) async {
    final trimmed = code.trim();
    if (!RegExp(r'^pair_[0-9a-f]{64}$').hasMatch(trimmed)) {
      throw const AiAssistantException('invalid_pairing_code');
    }
    final endpoint = _endpoint;
    if (endpoint == null ||
        endpoint.scheme != 'https' ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        endpoint.path != '/v1/assistant/ask') {
      throw const AiAssistantException('not_configured');
    }
    final uri = endpoint.replace(path: '/v1/assistant/pair');
    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'code': trimmed}),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401) {
        throw const AiAssistantException('invalid_pairing_code');
      }
      if (response.statusCode == 429) {
        throw const AiAssistantException('quota_exceeded');
      }
      if (response.statusCode != 200) {
        throw const AiAssistantException('service_unavailable');
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        throw const AiAssistantException('invalid_response');
      }
      final token = data['token'];
      final expiry = DateTime.tryParse(data['expiresAt']?.toString() ?? '');
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

  Future<void> unlink() => _store.clear();

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
