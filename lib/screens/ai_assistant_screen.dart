import 'package:flutter/material.dart';

import '../services/ai_assistant_client.dart';
import '../services/google_oracle_auth_client.dart';
import '../services/google_account_service.dart';
import '../services/oracle_ai_session_store.dart';
import '../services/oracle_account_client.dart';
import 'google_account_screen.dart';
import 'oracle_ai_pairing_screen.dart';

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
  String? _pendingQuestion;
  final List<({String question, String answer})> _history = [];
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
    try {
      if (OracleAccountClient.enabled) {
        final account = OracleAccountClient();
        try {
          final session = await account.currentSession();
          if (mounted) {
            setState(() => _oracleConnected = session?.isValid ?? false);
          }
        } finally {
          account.dispose();
        }
        return;
      }
      await GoogleAccountService.instance.initialize();
      final store = OracleAiSessionStore();
      final session = GoogleOracleAuthClient.enabled
          ? await store.readForGoogle(
              GoogleAccountService.instance.currentUser?.uid,
            )
          : await store.read();
      if (mounted) setState(() => _oracleConnected = session?.isValid ?? false);
    } catch (_) {
      if (mounted) setState(() => _oracleConnected = false);
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
    _client.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _pendingQuestion = _question.text.trim();
      _error = null;
    });
    final question = _question.text.trim();
    try {
      final answer = await _askWithGoogleRenewal();
      if (mounted) {
        setState(() {
          _history.add((question: question, answer: answer));
          _pendingQuestion = null;
        });
        _question.clear();
      }
    } on AiAssistantException catch (error) {
      if (mounted) setState(() {
        _pendingQuestion = null;
        _error = _message(error.code);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _pendingQuestion = null;
          _error = t('Unable to connect.', 'تعذّر الاتصال.');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
        await _refreshConnection();
      }
    }
  }

  /// Refresh the Google-linked Oracle session when missing or rejected.
  /// Only Google-backed sessions are automatically renewed; legacy pairing
  /// tokens continue to require explicit re-pairing.
  Future<String> _askWithGoogleRenewal() async {
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
      message: _question.text,
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

  // Lightweight display formatting for model responses. Do not interpret HTML
  // or execute links: all content remains plain, selectable text.
  Widget _answerText(String value) {
    final base = DefaultTextStyle.of(context).style;
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|\*([^*\n]+)\*');
    var cursor = 0;
    for (final match in pattern.allMatches(value)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1) ?? match.group(2) ?? '',
          style: match.group(1) != null
              ? base.copyWith(fontWeight: FontWeight.bold)
              : base.copyWith(fontStyle: FontStyle.italic),
        ),
      );
      cursor = match.end;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }
    return Directionality(
      textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
      child: SelectableText.rich(
        TextSpan(style: base, children: spans),
        textAlign: TextAlign.start,
      ),
    );
  }

  Widget _chatBubble({
    required String text,
    required bool fromUser,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: fromUser
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.84,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fromUser
                ? colors.primaryContainer
                : colors.surfaceContainerHighest,
            borderRadius: BorderRadiusDirectional.only(
              topStart: const Radius.circular(20),
              topEnd: const Radius.circular(20),
              bottomStart: Radius.circular(fromUser ? 20 : 6),
              bottomEnd: Radius.circular(fromUser ? 6 : 20),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: fromUser
                ? SelectableText(
                    text,
                    textDirection:
                        widget.arabic ? TextDirection.rtl : TextDirection.ltr,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.onPrimaryContainer,
                    ),
                  )
                : DefaultTextStyle(
                    style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                      height: 1.55,
                      color: colors.onSurface,
                    ),
                    child: _answerText(text),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Study assistant', 'المساعد الدراسي')),
        actions: [
          IconButton(
            tooltip: t('New conversation', 'محادثة جديدة'),
            onPressed: _loading
                ? null
                : () => setState(() {
                    _history.clear();
                    _pendingQuestion = null;
                    _error = null;
                    _question.clear();
                  }),
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_oracleConnected)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OracleAccountClient.enabled
                      ? OutlinedButton.icon(
                          onPressed: _loading || _connectingGoogle
                              ? null
                              : _signInToOracleAccount,
                          icon: const Icon(Icons.account_circle_outlined),
                          label: Text(t(
                            'Sign in to Masari',
                            'تسجيل الدخول إلى مساري',
                          )),
                        )
                      : GoogleOracleAuthClient.enabled
                      ? OutlinedButton.icon(
                          onPressed: _loading || _connectingGoogle
                              ? null
                              : () => _connectGoogle(),
                          icon: const Icon(Icons.account_circle_outlined),
                          label: Text(t(
                            'Continue with Google',
                            'المتابعة باستخدام Google',
                          )),
                        )
                      : OutlinedButton.icon(
                          onPressed: _loading
                              ? null
                              : () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => OracleAiPairingScreen(
                                        arabic: widget.arabic,
                                      ),
                                    ),
                                  );
                                  await _refreshConnection();
                                },
                          icon: const Icon(Icons.phonelink_lock_outlined),
                          label: Text(t('Pair AI device', 'ربط جهاز المساعد')),
                        ),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                children: [
                  if (_history.isEmpty) ...[
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: _chatBubble(
                        fromUser: false,
                        text: t(
                          'Hello! How can I help with your studies today?',
                          'مرحبًا! كيف يمكنني مساعدتك في دراستك اليوم؟',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        (t('Explain a topic', 'اشرح لي موضوعًا'),
                          t('Explain this topic in a simple way.',
                            'اشرح لي هذا الموضوع بطريقة مبسطة.')),
                        (t('Create revision questions', 'أنشئ أسئلة مراجعة'),
                          t('Create revision questions for me.',
                            'أنشئ لي أسئلة للمراجعة.')),
                        (t('Make a study plan', 'نظّم خطة مذاكرة'),
                          t('Help me make a study plan.',
                            'ساعدني في تنظيم خطة مذاكرة.')),
                      ].map((suggestion) => ActionChip(
                        label: Text(suggestion.$1),
                        onPressed: _loading
                            ? null
                            : () => setState(
                                () => _question.text = suggestion.$2,
                              ),
                      )).toList(),
                    ),
                  ],
                  for (final item in _history) ...[
                    _chatBubble(text: item.question, fromUser: true),
                    const SizedBox(height: 12),
                    _chatBubble(text: item.answer, fromUser: false),
                    const SizedBox(height: 20),
                  ],
                  if (_pendingQuestion != null) ...[
                    _chatBubble(text: _pendingQuestion!, fromUser: true),
                    const SizedBox(height: 12),
                  ],
                  if (_loading)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(t('Thinking…', 'يفكر المساعد…')),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(color: colors.onErrorContainer),
                      ),
                    ),
                    if (!OracleAccountClient.enabled &&
                        _error == _message('sign_in_required'))
                      TextButton.icon(
                        icon: const Icon(Icons.account_circle_outlined),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                GoogleAccountScreen(arabic: widget.arabic),
                          ),
                        ),
                        label: Text(t('Google account', 'حساب Google')),
                      ),
                  ],
                ],
              ),
            ),
            Material(
              color: colors.surface,
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _question,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 500,
                            enabled: !_loading,
                            textInputAction: TextInputAction.send,
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) {
                              if (!_loading && _question.text.trim().isNotEmpty) {
                                _ask();
                              }
                            },
                            decoration: InputDecoration(
                              hintText: t('Write your message…', 'اكتب رسالتك…'),
                              counterText: '',
                              filled: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: t('Send message', 'إرسال الرسالة'),
                          onPressed: _loading || _question.text.trim().isEmpty
                              ? null
                              : _ask,
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t(
                        'Your message is sent to the external AI service when you send it.',
                        'سيتم إرسال رسالتك إلى خدمة الذكاء الاصطناعي الخارجية عند الضغط على الإرسال.',
                      ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
