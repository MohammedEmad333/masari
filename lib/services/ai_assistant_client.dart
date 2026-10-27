import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'google_account_service.dart';

class AiAssistantException implements Exception {
  const AiAssistantException(this.code);

  final String code;

  @override
  String toString() => 'AiAssistantException($code)';
}

/// Only the user's explicitly submitted text is ever sent to this endpoint.
///
/// MASARI_AI_PROXY_URL is a PUBLIC HTTPS endpoint, not an API key.
class AiAssistantClient {
  AiAssistantClient({
    http.Client? client,
    Uri? endpoint,
    Future<String?> Function()? tokenProvider,
  }) : _http = client ?? http.Client(),
       _ownsClient = client == null,
       _endpoint = endpoint ?? Uri.tryParse(configuredUrl),
       _tokenProvider = tokenProvider ?? _firebaseToken;

  static const configuredUrl = String.fromEnvironment('MASARI_AI_PROXY_URL');

  static bool get isConfigured => _validEndpoint(Uri.tryParse(configuredUrl));

  final http.Client _http;
  final bool _ownsClient;
  final Uri? _endpoint;
  final Future<String?> Function() _tokenProvider;

  static bool _validEndpoint(Uri? uri) =>
      uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      uri.path == '/v1/assistant/ask';

  static Future<String?> _firebaseToken() async {
    await GoogleAccountService.instance.initialize();
    return GoogleAccountService.instance.currentUser?.getIdToken();
  }

  Future<String> ask({
    required String message,
    required String language,
    required bool consent,
  }) async {
    if (!consent) throw const AiAssistantException('consent_required');
    if (!_validEndpoint(_endpoint)) {
      throw const AiAssistantException('not_configured');
    }
    final prompt = message.trim();
    if (prompt.isEmpty || prompt.runes.length > 500) {
      throw const AiAssistantException('invalid_message');
    }
    if (!{'ar', 'en'}.contains(language)) {
      throw const AiAssistantException('invalid_language');
    }
    if (RegExp(
      r'authtoken|export_execute\.php|https?://|bearer\s|password\s*[:=]|AIza[0-9A-Za-z_-]{10,}',
      caseSensitive: false,
    ).hasMatch(prompt)) {
      throw const AiAssistantException('sensitive_content');
    }

    final String? idToken;
    try {
      idToken = await _tokenProvider();
    } catch (_) {
      throw const AiAssistantException('sign_in_required');
    }
    if (idToken == null || idToken.isEmpty) {
      throw const AiAssistantException('sign_in_required');
    }

    http.Response response;
    try {
      response = await _http
          .post(
            _endpoint!,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'message': prompt,
              'language': language,
              'consent': true,
            }),
          )
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const AiAssistantException('timeout');
    } catch (_) {
      throw const AiAssistantException('network_error');
    }
    if (response.statusCode == 401) {
      throw const AiAssistantException('sign_in_required');
    }
    if (response.statusCode == 429) {
      throw const AiAssistantException('quota_exceeded');
    }
    if (response.statusCode != 200) {
      throw const AiAssistantException('service_unavailable');
    }
    try {
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Invalid response');
      }
      final answer = payload['answer'];
      if (answer is! String || answer.trim().isEmpty) {
        throw const FormatException('Empty response');
      }
      return answer;
    } catch (_) {
      throw const AiAssistantException('invalid_response');
    }
  }

  void dispose() {
    if (_ownsClient) _http.close();
  }
}
