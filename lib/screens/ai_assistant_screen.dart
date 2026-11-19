import 'package:flutter/material.dart';

import '../services/ai_assistant_client.dart';
import '../services/google_oracle_auth_client.dart';
import '../services/google_account_service.dart';
import '../services/oracle_ai_session_store.dart';
import '../services/oracle_account_client.dart';
import 'google_account_screen.dart';
import 'oracle_ai_pairing_screen.dart';
import 'masari_chat_message_bubble.dart';
import 'masari_assistant_composer.dart';

/// Text-only AI chat. Sending happens only when the user taps Ask AI.
class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key, required this.arabic});

  final bool arabic;

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final _question = TextEditingController();
  final _client = AiAssistantClient();
  bool _loading = false;
  final List<({bool fromUser, String text})> _messages = [];
  final ScrollController _chatScrollController = ScrollController();
  bool _connectionChecked = false;
  String? _error;
  bool _oracleConnected = false;
  bool _connectingGoogle = false;

  @override
  void initState() {
    super.initState();
    _refreshConnection();
    if (!OracleAccountClient.enabled && GoogleOracleAuthClient.enabled) {
      _connectGoogle(silent: true);
    }
  }

  Future<void> _connectGoogle({bool silent = false}) async {
    if (_connectingGoogle) return;
    setState(() => _connectingGoogle = true);
    final client = GoogleOracleAuthClient();
    try {
      await GoogleAccountService.instance.initialize();
      if (GoogleAccountService.instance.currentUser == null) {
        if (silent || !mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GoogleAccountScreen(arabic: widget.arabic),
          ),
        );
      }
      if (GoogleAccountService.instance.currentUser == null) return;
      await client.exchange();
      await _refreshConnection();
    } on AiAssistantException catch (error) {
      if (mounted && !silent) setState(() => _error = _message(error.code));
    } catch (_) {
      if (mounted && !silent) {
        setState(
          () =>
              _error = t('Google connection failed.', 'تعذّر ربط حساب Google.'),
        );
      }
    } finally {
      client.dispose();
      if (mounted) setState(() => _connectingGoogle = false);
    }
  }

  Future<void> _refreshConnection() async {
    var connected = false;
    try {
      if (OracleAccountClient.enabled) {
        final account = OracleAccountClient();
        try {
          final session = await account.currentSession();
          connected = session?.isValid ?? false;
        } finally {
          account.dispose();
        }
      } else {
        await GoogleAccountService.instance.initialize();
        final store = OracleAiSessionStore();
        final session = GoogleOracleAuthClient.enabled
            ? await store.readForGoogle(
                GoogleAccountService.instance.currentUser?.uid,
              )
            : await store.read();
        connected = session?.isValid ?? false;
      }
    } catch (_) {
      connected = false;
    }
    if (mounted) {
      setState(() {
        _oracleConnected = connected;
        _connectionChecked = true;
      });
    }
  }

  Future<void> _signInToOracleAccount() async {
    if (_connectingGoogle || _loading) return;
    setState(() {
      _connectingGoogle = true;
      _error = null;
    });
    final account = OracleAccountClient();
    try {
      await account.signIn();
      await _refreshConnection();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = t(
            'Could not sign in to Masari. Try again from your account.',
            'تعذّر تسجيل الدخول إلى مساري. حاول مجددًا من حسابك.',
          ),
        );
      }
    } finally {
      account.dispose();
      if (mounted) setState(() => _connectingGoogle = false);
    }
  }

  String t(String en, String ar) => widget.arabic ? ar : en;

  @override
  void dispose() {
    _question.dispose();
    _chatScrollController.dispose();
    _client.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    if (_loading) return;
    final message = _question.text.trim();
    if (message.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _messages.add((fromUser: true, text: message));
      _question.clear();
      _loading = true;
      _error = null;
    });
    _scrollToBottom();

    try {
      final answer = await _askWithGoogleRenewal(message);
      if (mounted) {
        setState(() => _messages.add((fromUser: false, text: answer)));
        _scrollToBottom();
      }
    } on AiAssistantException catch (error) {
      if (mounted) {
        setState(() => _error = _message(error.code));
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = t('Unable to connect.', 'تعذّر الاتصال.'));
        _scrollToBottom();
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        await _refreshConnection();
      }
    }
  }

  /// Refresh the Google-linked Oracle session when missing or rejected.
  /// Only Google-backed sessions are automatically renewed; legacy pairing
  /// tokens continue to require explicit re-pairing.
  Future<String> _askWithGoogleRenewal(String message) async {
    if (!OracleAccountClient.enabled && GoogleOracleAuthClient.enabled) {
      await GoogleAccountService.instance.initialize();
      final session = await OracleAiSessionStore().readForGoogle(
        GoogleAccountService.instance.currentUser?.uid,
      );
      if (session == null) {
        final google = GoogleOracleAuthClient();
        try {
          await google.exchange();
        } finally {
          google.dispose();
        }
      }
    }
    Future<String> send() => _client.ask(
      message: message,
      language: widget.arabic ? 'ar' : 'en',
    );
    try {
      return await send();
    } on AiAssistantException catch (error) {
      if (OracleAccountClient.enabled ||
          !GoogleOracleAuthClient.enabled ||
          error.code != 'oracle_session_expired') {
        rethrow;
      }
      final google = GoogleOracleAuthClient();
      try {
        await google.exchange();
      } finally {
        google.dispose();
      }
      return send(); // Retry exactly once after authenticated renewal.
    }
  }

  String _message(String code) {
    switch (code) {
      case 'sign_in_required':
        return t(
          'Sign in with Google first.',
          'سجّل الدخول بحساب Google أولاً.',
        );
      case 'google_auth_rejected':
        return t(
          'Google identity was rejected by Oracle. Check Firebase sign-in and token verification.',
          'رفض Oracle هوية Google. تحقق من إعدادات Firebase والتحقق من رمز الدخول.',
        );
      case 'google_auth_forbidden':
        return t(
          'Oracle denied Google account access. Check the Google provider configuration.',
          'رفض Oracle صلاحية حساب Google. تحقق من إعدادات مزوّد Google.',
        );
      case 'network_error':
        return t(
          'Could not reach Oracle. Check your connection and try again.',
          'تعذّر الاتصال بخادم Oracle. تحقق من الإنترنت وحاول مجددًا.',
        );
      case 'invalid_response':
        return t(
          'Oracle returned an invalid response.',
          'أعاد خادم Oracle استجابة غير صالحة.',
        );
      case 'not_configured':
        return t(
          'The assistant connection is not configured in this build.',
          'اتصال المساعد غير مُعدّ في هذه النسخة.',
        );
      case 'app_check_token_unavailable':
        return t(
          'Could not verify this device with Play Integrity. Check Google Play services and try again.',
          'تعذّر التحقق من الجهاز عبر Play Integrity. تحقق من خدمات Google Play وحاول مجددًا.',
        );
      case 'app_check_failed':
        return t(
          'App verification was rejected by the server. Check your app registration.',
          'رفض الخادم التحقق من التطبيق. تحقق من تسجيل التطبيق.',
        );
      case 'oracle_access_denied':
        return t(
          'The Masari server denied this request. Check your account access.',
          'رفض خادم مساري هذا الطلب. تحقق من صلاحيات حسابك.',
        );
      case 'oracle_session_expired':
        return t(
          OracleAccountClient.enabled
              ? 'Your Masari session expired. Sign in to your account again.'
              : 'Your Oracle AI session has expired or was revoked. Re-pair the device.',
          OracleAccountClient.enabled
              ? 'انتهت جلسة مساري. سجّل الدخول إلى حسابك مجددًا.'
              : 'انتهت جلسة مساعد Oracle أو أُلغيت. يلزم إعادة ربط الجهاز.',
        );
      case 'session_storage_error':
        return t(
          'Secure session storage is unavailable.',
          'تعذّر الوصول إلى التخزين الآمن لجلسة المساعد.',
        );
      case 'quota_exceeded':
        return t('Daily or minute limit reached.', 'وصلت إلى حد الاستخدام.');
      case 'invalid_message':
        return t('Enter a shorter question.', 'أدخل سؤالًا أقصر.');
      case 'sensitive_content':
        return t(
          'Do not include links, passwords or calendar tokens.',
          'لا تُدخل روابط أو كلمات مرور أو رموز التقويم.',
        );
      case 'timeout':
        return t('The model took too long.', 'استغرق النموذج وقتًا طويلًا.');
      default:
        return t(
          'The AI service is unavailable. Try again later.',
          'خدمة الذكاء الاصطناعي غير متاحة. حاول لاحقًا.',
        );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_chatScrollController.hasClients) return;
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _startNewChat() {
    FocusScope.of(context).unfocus();
    setState(() {
      _messages.clear();
      _error = null;
      _question.clear();
    });
  }

  void _usePrompt(String prompt) {
    _question.value = TextEditingValue(
      text: prompt,
      selection: TextSelection.collapsed(offset: prompt.length),
    );
    FocusScope.of(context).requestFocus(FocusNode());
  }

  Widget _welcomeContent() {
    final prompts = widget.arabic
        ? const [
            'اشرح لي مفهومًا دراسيًا',
            'ساعدني في تنظيم المذاكرة',
            'لخّص هذا الموضوع',
          ]
        : const [
            'Explain a study concept',
            'Help me plan revision',
            'Summarize this topic',
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MasariChatMessageBubble(
          text: t(
            'Hello! How can I help with your studies today?',
            'مرحبًا! كيف يمكنني مساعدتك في دراستك اليوم؟',
          ),
          fromUser: false,
          arabic: widget.arabic,
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 40, bottom: 8),
          child: Text(
            t('You can start with one of these:', 'يمكنك البدء بأحد هذه الأسئلة:'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 40),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: prompts
                .map(
                  (prompt) => ActionChip(
                    label: Text(prompt),
                    onPressed: () => _usePrompt(prompt),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _typingIndicator() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: scheme.secondaryContainer,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 17,
              color: scheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(t('Assistant is typing…', 'المساعد يكتب...')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget? _accountAction() {
    if (!_connectionChecked || _oracleConnected || _connectingGoogle) {
      return null;
    }
    if (OracleAccountClient.enabled) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          onPressed: _loading ? null : _signInToOracleAccount,
          icon: const Icon(Icons.account_circle_outlined),
          label: Text(t('Sign in to Masari', 'تسجيل الدخول إلى مساري')),
        ),
      );
    }
    if (GoogleOracleAuthClient.enabled) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          onPressed: _loading ? null : () => _connectGoogle(),
          icon: const Icon(Icons.account_circle_outlined),
          label: Text(t('Continue with Google', 'المتابعة باستخدام Google')),
        ),
      );
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: OutlinedButton.icon(
        onPressed: _loading
            ? null
            : () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        OracleAiPairingScreen(arabic: widget.arabic),
                  ),
                );
                await _refreshConnection();
              },
        icon: const Icon(Icons.phonelink_lock_outlined),
        label: Text(t('Pair AI device', 'ربط جهاز المساعد')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountAction = _accountAction();
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Study assistant', 'المساعد الدراسي')),
        actions: [
          IconButton(
            tooltip: t('New chat', 'محادثة جديدة'),
            onPressed: _startNewChat,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _chatScrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                children: [
                  if (_messages.isEmpty) _welcomeContent(),
                  for (final message in _messages)
                    MasariChatMessageBubble(
                      text: message.text,
                      fromUser: message.fromUser,
                      arabic: widget.arabic,
                    ),
                  if (_loading) _typingIndicator(),
                  if (_error != null) ...[
                    MasariChatMessageBubble(
                      text: _error!,
                      fromUser: false,
                      arabic: widget.arabic,
                      isError: true,
                    ),
                    if (!OracleAccountClient.enabled &&
                        _error == _message('sign_in_required'))
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.account_circle_outlined),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => GoogleAccountScreen(
                                arabic: widget.arabic,
                              ),
                            ),
                          ),
                          label: Text(t('Google account', 'حساب Google')),
                        ),
                      ),
                  ],
                  if (accountAction != null) accountAction,
                ],
              ),
            ),
            MasariAssistantComposer(
              controller: _question,
              arabic: widget.arabic,
              loading: _loading,
              onSend: _ask,
            ),
          ],
        ),
      ),
    );
  }

}
